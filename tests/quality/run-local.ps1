param(
 [Parameter(Mandatory=$true)][string]$RuntimeDirectory,
 [Parameter(Mandatory=$true)][string]$TestDirectory,
 [Parameter(Mandatory=$true)][string]$NodeExecutable,
 [int]$Port=55439
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
 Invoke-QualitySql (Join-Path $PSScriptRoot 'local-bootstrap.sql') 'bootstrap.txt'
 $qualityMigrationScript=Join-Path $qualityRoot 'migrations.sql'
 $qualityIncludes=Get-ChildItem (Join-Path $qualityRepo 'supabase/migrations') -File | Sort-Object Name | ForEach-Object {
  if($_.Name -like '*_quality_source_stock_v1.sql'){
   "\i '"+(Join-Path $PSScriptRoot 'pre-source-fixture.sql').Replace('\','/').Replace("'","''")+"'"
  }
  "\i '"+$_.FullName.Replace('\','/').Replace("'","''")+"'"
 }
 $qualityIncludes | Set-Content -LiteralPath $qualityMigrationScript
 Invoke-QualitySql $qualityMigrationScript 'migrations.txt'
 Get-ChildItem $PSScriptRoot -Filter '*.test.sql' -File | Sort-Object Name | ForEach-Object {Invoke-QualitySql $_.FullName ($_.Name+'.txt')}
 & $NodeExecutable (Join-Path $PSScriptRoot 'concurrency.mjs') $qualityBin $Port $qualityResults *> (Join-Path $qualityResults 'concurrency-run.txt')
 if($LASTEXITCODE){throw 'Concurrent PostgreSQL tests failed; inspect results'}
 "Standalone PostgreSQL tests passed. Supabase service integration was not tested." | Set-Content (Join-Path $qualityResults 'summary.txt')
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
