param([Parameter(Mandatory=$true)][string]$RuntimeDirectory,[int]$Port=55460,[switch]$Upgrade,[switch]$SkipConcurrency,[switch]$ReportingApi)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('FactoryLean-Reporting-M3A-'+[guid]::NewGuid().ToString('N'))
$bin=Join-Path $RuntimeDirectory 'pgsql/bin'
$data=Join-Path $root 'data'
$results=Join-Path $root 'results'
New-Item -ItemType Directory -Path $results -Force | Out-Null
Write-Output "Evidence: $root"
$inputHashes=[ordered]@{}
$inputs=@(Get-ChildItem -LiteralPath $PSScriptRoot -File)+@(Get-ChildItem (Join-Path $repo 'supabase/migrations') -File | Where-Object Name -ne '20261006072000_factory_export_reader.sql')
foreach($f in $inputs){$inputHashes[$f.FullName]=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash}
$inputHashes | ConvertTo-Json | Set-Content (Join-Path $results 'input-hashes.json')
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$Port)
try{$listener.Start()}finally{$listener.Stop()}
& (Join-Path $bin 'postgres.exe') --version | Set-Content (Join-Path $results 'version.txt')
& (Join-Path $bin 'initdb.exe') -D $data -U quality_fixture --encoding=UTF8 --locale=C --auth=trust *> (Join-Path $results 'initdb.txt')
if($LASTEXITCODE){throw 'initdb failed'}
Add-Content -LiteralPath (Join-Path $data 'postgresql.conf') -Value "`nlisten_addresses='127.0.0.1'`nport=$Port`ntimezone='UTC'`n"
$started=$false
try {
 $starter=Start-Process -FilePath (Join-Path $bin 'pg_ctl.exe') -ArgumentList @('-D',('"'+$data+'"'),'-l',('"'+(Join-Path $root 'postgres.log')+'"'),'-w','start') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $results 'start.txt') -RedirectStandardError (Join-Path $results 'start-error.txt')
 if(-not $starter.WaitForExit(30000) -or $starter.ExitCode){throw 'start failed'}
 $started=$true
 & (Join-Path $bin 'createdb.exe') -h 127.0.0.1 -p $Port -U quality_fixture factory_lean_quality_local
 if($LASTEXITCODE){throw 'createdb failed'}
 function RunSql([string]$file,[string]$name){
  # Windows PowerShell treats harmless PostgreSQL NOTICE stderr as an exception.
  $prior=$ErrorActionPreference
  try{$ErrorActionPreference='Continue'
   & (Join-Path $bin 'psql.exe') -X -h 127.0.0.1 -p $Port -U quality_fixture -d factory_lean_quality_local -v ON_ERROR_STOP=1 -f $file *> (Join-Path $results $name)
   $code=$LASTEXITCODE
  }finally{$ErrorActionPreference=$prior}
  if($code){throw "SQL failed: $name"}
 }
 RunSql (Join-Path $repo 'tests/quality/local-bootstrap.sql') 'bootstrap.txt'

 $m3=Join-Path $repo 'supabase/migrations/20261019091907_production_reporting_v3_m3a.sql'
 $migrations=Get-ChildItem (Join-Path $repo 'supabase/migrations') -File | Where-Object Name -ne '20261006072000_factory_export_reader.sql' | Sort-Object Name
 $baseline=$migrations | Where-Object FullName -ne $m3
 if(@($baseline).Count -ne 92){throw 'Unexpected pre-M3A baseline'}
 $includes=$baseline | ForEach-Object {
 if($_.Name -eq '20261010061827_quality_source_stock_v1.sql'){"\i '"+(Join-Path $repo 'tests/quality/pre-source-fixture.sql').Replace('\','/')+"'"}
 "\i '"+$_.FullName.Replace('\','/').Replace("'","''")+"'"}
 $includes | Set-Content (Join-Path $root 'baseline.sql')
 RunSql (Join-Path $root 'baseline.sql') 'baseline.txt'
 if(-not $Upgrade){
  RunSql (Join-Path $PSScriptRoot 'before.sql') 'compatibility-before.txt'
  RunSql $m3 'm3a.txt'
  RunSql (Join-Path $PSScriptRoot 'after.sql') 'compatibility-after.txt'
 }
 RunSql (Join-Path $repo 'tests/maintenance-planning/fixture.sql') 'fixture.txt'
 RunSql (Join-Path $repo 'tests/production-late-recording/fixture.sql') 'm2-fixture.txt'
 RunSql (Join-Path $repo 'tests/production-late-recording/writer.test.sql') 'writer.txt'
 RunSql (Join-Path $PSScriptRoot 'seed.sql') 'seed.txt'
 if($Upgrade){
  RunSql (Join-Path $PSScriptRoot 'before.sql') 'compatibility-before.txt'
  RunSql $m3 'm3a.txt'
  RunSql (Join-Path $PSScriptRoot 'after.sql') 'compatibility-after.txt'
 }
 RunSql (Join-Path $PSScriptRoot 'reporting.test.sql') 'reporting.txt'
 RunSql (Join-Path $PSScriptRoot 'security.test.sql') 'security.txt'
 RunSql (Join-Path $PSScriptRoot 'temporal.test.sql') 'temporal.txt'
 RunSql (Join-Path $PSScriptRoot 'multiple.test.sql') 'multiple.txt'
 RunSql (Join-Path $PSScriptRoot 'performance.test.sql') 'performance.txt'
 if($ReportingApi){
  & node (Join-Path $PSScriptRoot 'http.mjs') $bin $Port $results *> (Join-Path $results 'http.txt')
  if($LASTEXITCODE){throw 'M3B HTTP integration failed'}
 }
 RunSql (Join-Path $repo 'tests/production-late-recording/boundary.test.sql') 'boundary.txt'
 RunSql (Join-Path $repo 'tests/production-late-recording/maintenance.test.sql') 'maintenance.txt'
 RunSql (Join-Path $repo 'tests/production-late-recording/startup.test.sql') 'startup.txt'
 if(-not $SkipConcurrency){
 & node (Join-Path $repo 'tests/production-late-recording/concurrency.mjs') $bin $Port $results *> (Join-Path $results 'concurrency.txt')
 if($LASTEXITCODE){throw 'M2 concurrency failed under M3A'}
 }
 RunSql (Join-Path $repo 'tests/maintenance-planning/readiness-fixture.sql') 'readiness-fixture.txt'
 RunSql (Join-Path $repo 'tests/maintenance-planning/recording.test.sql') 'wip-recording.txt'
 RunSql (Join-Path $repo 'tests/maintenance-planning/readiness.test.sql') 'readiness.txt'
 RunSql (Join-Path $repo 'tests/maintenance-planning/transfers.test.sql') 'transfers.txt'
 RunSql (Join-Path $repo 'tests/quality/source-stock.test.sql') 'source-stock.txt'
 RunSql (Join-Path $repo 'tests/quality/release-fixes.test.sql') 'quality-release-fixes.txt'
 RunSql (Join-Path $PSScriptRoot 'final.sql') 'final.txt'
 foreach($f in $inputHashes.Keys){if((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash -ne $inputHashes[$f]){throw "Test input changed during execution: $f"}}
 "PASS: M3A reporting/security/compatibility tests. Upgrade=$Upgrade; SkipConcurrency=$SkipConcurrency; Export Reader excluded. Standalone PostgreSQL, not hosted Supabase." | Set-Content (Join-Path $results 'summary.txt')
 Get-Content (Join-Path $results 'summary.txt')

}finally{
 if($started){
  & (Join-Path $bin 'pg_ctl.exe') -D $data -m fast -w stop *> (Join-Path $results 'stop.txt')
  if($LASTEXITCODE){throw 'Failed to stop owned PostgreSQL; data retained'}
 }
 $resolved=[IO.Path]::GetFullPath($data)
 $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if($root.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $root -Leaf).StartsWith('FactoryLean-Reporting-M3A-') -and $resolved.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
  Remove-Item -LiteralPath $resolved -Recurse -Force
 }else{throw 'Unexpected disposable data path; deletion refused'}
}
