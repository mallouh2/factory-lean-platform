param(
 [Parameter(Mandatory=$true)][string]$RuntimeDirectory,
 [Parameter(Mandatory=$true)][string]$TestDirectory,
 [Parameter(Mandatory=$true)][string]$NodeExecutable,
 [int]$Port=55439,
 [switch]$ReadersOnly,
 [switch]$ConcurrencyOnly,
 [switch]$StopsOnly,
 [switch]$StopAssertionsOnly,
 [switch]$ReadinessOnly,
 [switch]$LossOnly,
 [switch]$BoardOnly,
 [switch]$ActivationOnly
)
$ErrorActionPreference='Stop'
$qualityRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$qualityTempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$qualityRoot=[IO.Path]::GetFullPath($TestDirectory)
if(-not $qualityRoot.StartsWith($qualityTempRoot,[StringComparison]::OrdinalIgnoreCase) -or
 -not (Split-Path $qualityRoot -Leaf).StartsWith('FactoryLean-Quality-Postgres-')) { throw 'Dedicated Quality temporary directory required' }
$qualityBin=Join-Path $RuntimeDirectory 'pgsql/bin'
$qualityData=Join-Path $qualityRoot 'data'
$qualityLog=Join-Path $qualityRoot 'postgres.log'
$qualityResults=Join-Path $qualityRoot 'results'
New-Item -ItemType Directory -Force -Path $qualityResults | Out-Null
if(Test-Path -LiteralPath $qualityData){throw 'Refusing to reuse or overwrite a database'}
$qualityListener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$Port)
try{$qualityListener.Start()}finally{$qualityListener.Stop()}
& (Join-Path $qualityBin 'initdb.exe') -D $qualityData -U quality_fixture --encoding=UTF8 --locale=C --auth=trust *> (Join-Path $qualityResults 'initdb.txt')
if($LASTEXITCODE){throw 'initdb failed'}
Add-Content -LiteralPath (Join-Path $qualityData 'postgresql.conf') -Value "`nlisten_addresses='127.0.0.1'`nport=$Port`n"
$qualityStarted=$false
try {
 $qualityStarter=Start-Process -FilePath (Join-Path $qualityBin 'pg_ctl.exe') -ArgumentList @('-D',('"'+$qualityData+'"'),'-l',('"'+$qualityLog+'"'),'-w','start') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $qualityResults 'start.txt') -RedirectStandardError (Join-Path $qualityResults 'start-error.txt')
 if(-not $qualityStarter.WaitForExit(30000) -or $qualityStarter.ExitCode){throw 'PostgreSQL start failed'}
 $qualityStarted=$true
 & (Join-Path $qualityBin 'createdb.exe') -h 127.0.0.1 -p $Port -U quality_fixture factory_lean_quality_local
 if($LASTEXITCODE){throw 'Database creation failed'}
 function Invoke-QualitySql([string]$File,[string]$ResultName){
  & (Join-Path $qualityBin 'psql.exe') -X -h 127.0.0.1 -p $Port -U quality_fixture -d factory_lean_quality_local -v ON_ERROR_STOP=1 -f $File *> (Join-Path $qualityResults $ResultName)
  if($LASTEXITCODE){throw "SQL failed: $ResultName; inspect results"}
 }
 Invoke-QualitySql (Join-Path $qualityRepo 'tests/quality/local-bootstrap.sql') 'bootstrap.txt'
 $qualityMigrationScript=Join-Path $qualityRoot 'migrations.sql'
 $qualityIncludes=Get-ChildItem (Join-Path $qualityRepo 'supabase/migrations') -File | Where-Object Name -ne '20261006072000_factory_export_reader.sql' | Sort-Object Name | ForEach-Object {
  if($_.Name -like '*_quality_source_stock_v1.sql'){
   "\i '"+(Join-Path $qualityRepo 'tests/quality/pre-source-fixture.sql').Replace('\','/').Replace("'","''")+"'"
  }
  "\i '"+$_.FullName.Replace('\','/').Replace("'","''")+"'"
 }
 $qualityIncludes | Set-Content -LiteralPath $qualityMigrationScript
 Invoke-QualitySql $qualityMigrationScript 'migrations.txt'
 Invoke-QualitySql (Join-Path $PSScriptRoot 'fixture.sql') 'fixture.txt'
 Invoke-QualitySql (Join-Path $PSScriptRoot 'readiness-fixture.sql') 'readiness-fixture.txt'
 if(-not $ConcurrencyOnly){
 Get-ChildItem $PSScriptRoot -Filter '*.test.sql' -File | Where-Object {(-not $ReadersOnly -or $_.Name -like 'reader*.test.sql') -and (-not $StopAssertionsOnly -or $_.Name -in @('stops.test.sql','transfers.test.sql')) -and (-not $ReadinessOnly -or $_.Name -in @('readiness.test.sql','transfers.test.sql','reservations.test.sql','recording.test.sql')) -and (-not $LossOnly -or $_.Name -in @('loss.test.sql','stops.test.sql','recording.test.sql')) -and (-not $BoardOnly -or $_.Name -in @('board.test.sql','reader-resources.test.sql')) -and (-not $ActivationOnly -or $_.Name -in @('activation.test.sql','reader-contract.test.sql','stops.test.sql','readiness.test.sql','loss.test.sql'))} | Sort-Object Name | ForEach-Object {Invoke-QualitySql $_.FullName ($_.Name+'.txt')}
 }
 if($ReadinessOnly -and -not $ConcurrencyOnly){
 $readinessPrelude=Join-Path $qualityRoot 'execution-prelude.sql'
 @'
 do $$declare x jsonb;begin
 if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Local fixture only';end if;
 x:=mp_test.fixture('execution-regression');update public.factories set is_demo=true where id=(x->>'factory')::uuid;
 end$$;
'@ | Set-Content -LiteralPath $readinessPrelude
 Invoke-QualitySql $readinessPrelude 'execution-prelude.txt'
 Invoke-QualitySql (Join-Path $qualityRepo 'tests/production-execution.test.sql') 'production-execution.txt'
 }
 if($ActivationOnly){
 & $NodeExecutable (Join-Path $PSScriptRoot 'activation-concurrency.mjs') $qualityBin $Port $qualityResults *> (Join-Path $qualityResults 'activation-concurrency.txt')
 if($LASTEXITCODE){throw 'Activation concurrency tests failed'}
 }elseif($BoardOnly){
 Invoke-QualitySql (Join-Path $PSScriptRoot 'board-performance.sql') 'board-performance.txt'
 }elseif($LossOnly){
 & $NodeExecutable (Join-Path $PSScriptRoot 'loss-concurrency.mjs') $qualityBin $Port $qualityResults *> (Join-Path $qualityResults 'loss-concurrency-run.txt')
 if($LASTEXITCODE){throw 'Maintenance Loss tests failed; inspect results'}
 }elseif($ReadinessOnly){
 & $NodeExecutable (Join-Path $PSScriptRoot 'readiness-concurrency.mjs') $qualityBin $Port $qualityResults *> (Join-Path $qualityResults 'readiness-concurrency-run.txt')
 if($LASTEXITCODE){throw 'Readiness concurrency tests failed; inspect results'}
 }elseif($StopsOnly){
 & $NodeExecutable (Join-Path $PSScriptRoot 'concurrency.mjs') $qualityBin $Port $qualityResults *> (Join-Path $qualityResults 'concurrency-run.txt')
 if($LASTEXITCODE){throw 'Maintenance concurrency regressions failed; inspect results'}
 & $NodeExecutable (Join-Path $PSScriptRoot 'stops-concurrency.mjs') $qualityBin $Port $qualityResults *> (Join-Path $qualityResults 'stops-concurrency-run.txt')
 if($LASTEXITCODE){throw 'Actual-stop concurrency tests failed; inspect results'}
 & $NodeExecutable (Join-Path $PSScriptRoot 'contract-concurrency.mjs') $qualityBin $Port $qualityResults *> (Join-Path $qualityResults 'contract-concurrency-run.txt')
 if($LASTEXITCODE){throw 'Maintenance contract concurrency regressions failed; inspect results'}
 }elseif(-not $ReadersOnly){
 if(-not $ConcurrencyOnly){
 Get-ChildItem (Join-Path $qualityRepo 'tests/quality') -Filter '*.test.sql' -File | Sort-Object Name | ForEach-Object {Invoke-QualitySql $_.FullName ($_.Name+'.txt')}
 }
 & $NodeExecutable (Join-Path $PSScriptRoot 'concurrency.mjs') $qualityBin $Port $qualityResults *> (Join-Path $qualityResults 'concurrency-run.txt')
 if($LASTEXITCODE){throw 'Concurrent PostgreSQL tests failed; inspect results'}
 & $NodeExecutable (Join-Path $qualityRepo 'tests/quality/concurrency.mjs') $qualityBin $Port $qualityResults *> (Join-Path $qualityResults 'quality-concurrency-run.txt')
 if($LASTEXITCODE){throw 'Existing Quality concurrency regressions failed; inspect results'}
 & $NodeExecutable (Join-Path $PSScriptRoot 'readers-concurrency.mjs') $qualityBin $Port $qualityResults *> (Join-Path $qualityResults 'readers-concurrency-run.txt')
 if($LASTEXITCODE){throw 'Reader concurrency regressions failed; inspect results'}
 & $NodeExecutable (Join-Path $PSScriptRoot 'contract-concurrency.mjs') $qualityBin $Port $qualityResults *> (Join-Path $qualityResults 'contract-concurrency-run.txt')
 if($LASTEXITCODE){throw 'Preview-to-confirmation concurrency tests failed; inspect results'}
 }
 if($ActivationOnly){'Activation and affected contract/stop/readiness/Loss rollback suites and activation races passed locally; no remote access.' | Set-Content (Join-Path $qualityResults 'summary.txt')}elseif($BoardOnly){'Operational board scoped SQL/readers and query plans passed locally. No hosted services or activation; Export Reader excluded.' | Set-Content (Join-Path $qualityResults 'summary.txt')}elseif($LossOnly){'Maintenance Loss/actual-stop/recording SQL and calculation/persistence races passed locally; no hosted acceptance or activation. Export Reader excluded.' | Set-Content (Join-Path $qualityResults 'summary.txt')}elseif($ReadinessOnly){'Readiness and affected execution/Maintenance tests passed. No hosted services, activation or Quality/Warehouse suites. Export Reader excluded.' | Set-Content (Join-Path $qualityResults 'summary.txt')}elseif($StopsOnly){'Maintenance actual-stop/contract races passed; selected Maintenance rollback assertions passed. No Quality suites or hosted services tested. Export Reader excluded.' | Set-Content (Join-Path $qualityResults 'summary.txt')}elseif($ConcurrencyOnly){'Concurrency tests only; rollback SQL suites not run.' | Set-Content (Join-Path $qualityResults 'summary.txt')}elseif($ReadersOnly){'Reader rollback SQL only; broad regressions not run.' | Set-Content (Join-Path $qualityResults 'summary.txt')}else{
 "Maintenance Planning and existing Quality standalone PostgreSQL tests passed. Export Reader excluded. Supabase services not tested." | Set-Content (Join-Path $qualityResults 'summary.txt')
 }
} finally {
 if($qualityStarted){
  & (Join-Path $qualityBin 'pg_ctl.exe') -D $qualityData -m fast -w stop *> (Join-Path $qualityResults 'stop.txt')
  if($LASTEXITCODE){throw 'Failed to stop isolated PostgreSQL; retain data and investigate'}
 }
 # Absolute target checked before recursive deletion, only our fresh disposable data.
 $qualityResolvedData=[IO.Path]::GetFullPath($qualityData)
 if($qualityResolvedData.StartsWith($qualityRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
  Remove-Item -LiteralPath $qualityResolvedData -Recurse -Force
 }
}
