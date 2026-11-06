param([Parameter(Mandatory=$true)][string]$RuntimeDirectory,[int]$Port=55472,[switch]$Upgrade,[switch]$Smoke,[switch]$ConsumerOnly)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('FactoryLean-Consumers-M3C-'+[guid]::NewGuid().ToString('N'))
$bin=Join-Path $RuntimeDirectory 'pgsql/bin';$data=Join-Path $root 'data';$results=Join-Path $root 'results'
New-Item -ItemType Directory -Path $results | Out-Null
Write-Output "Evidence: $root"
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$Port)
try{$listener.Start()}finally{$listener.Stop()}
& (Join-Path $bin 'initdb.exe') -D $data -U quality_fixture --encoding=UTF8 --locale=C --auth=trust *> (Join-Path $results 'initdb.txt')
if($LASTEXITCODE){throw 'initdb failed'}
Add-Content -LiteralPath (Join-Path $data 'postgresql.conf') -Value "`nlisten_addresses='127.0.0.1'`nport=$Port`ntimezone='UTC'`n"
$started=$false
try{
 $p=Start-Process -FilePath (Join-Path $bin 'pg_ctl.exe') -ArgumentList @('-D',('"'+$data+'"'),'-l',('"'+(Join-Path $root 'postgres.log')+'"'),'-w','start') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $results 'start.txt') -RedirectStandardError (Join-Path $results 'start-error.txt')
 if(-not $p.WaitForExit(30000) -or $p.ExitCode){throw 'start failed'};$started=$true
 & (Join-Path $bin 'createdb.exe') -h 127.0.0.1 -p $Port -U quality_fixture factory_lean_quality_local
 if($LASTEXITCODE){throw 'createdb failed'}
 function RunSql([string]$file,[string]$name){
  $prior=$ErrorActionPreference
  try{$ErrorActionPreference='Continue'; & (Join-Path $bin 'psql.exe') -X -h 127.0.0.1 -p $Port -U quality_fixture -d factory_lean_quality_local -v ON_ERROR_STOP=1 -f $file *> (Join-Path $results $name);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$prior}
  if($code){throw "SQL failed: $name"}
 }
 RunSql (Join-Path $repo 'tests/quality/local-bootstrap.sql') 'bootstrap.txt'
 $migration=Join-Path $repo 'supabase/migrations/20261019124124_production_scrap_lean_consumers_v3_m3c.sql'
 $baseline=@(Get-ChildItem (Join-Path $repo 'supabase/migrations') -File | Where-Object {$_.Name -ne '20261006072000_factory_export_reader.sql' -and $_.FullName -ne $migration} | Sort-Object Name)
 if($baseline.Count -ne 94){throw 'Unexpected pre-M3C migration chain'}
 $hashes=[ordered]@{}
 foreach($file in @($baseline)+(Get-Item $migration)+@(Get-ChildItem -LiteralPath $PSScriptRoot -File)){$hashes[$file.FullName]=(Get-FileHash -LiteralPath $file.FullName).Hash}
 foreach($file in @('src/app/api/lean/route.ts','src/utils/lean-comparison.mjs','src/utils/lean-contract.mjs','src/utils/production-reporting.mjs','src/utils/production-periods.mjs','src/utils/production-consumer-transport.mjs','src/utils/exact-json.mjs','supabase/functions/lean-comparison/index.ts','tests/production-consumers.test.mjs')){$absolute=Join-Path $repo $file;$hashes[$absolute]=(Get-FileHash -LiteralPath $absolute).Hash}
 $hashes | ConvertTo-Json | Set-Content (Join-Path $results 'input-hashes.json')
 $includes=$baseline | ForEach-Object{if($_.Name -eq '20261010061827_quality_source_stock_v1.sql'){"\i '"+(Join-Path $repo 'tests/quality/pre-source-fixture.sql').Replace('\','/')+"'"};"\i '"+$_.FullName.Replace('\','/')+"'"}
 $includes | Set-Content (Join-Path $root 'baseline.sql');RunSql (Join-Path $root 'baseline.sql') 'baseline.txt'
 function Fixtures{
  RunSql (Join-Path $repo 'tests/maintenance-planning/fixture.sql') 'mp-fixture.txt'
  RunSql (Join-Path $repo 'tests/production-late-recording/fixture.sql') 'late-fixture.txt'
  RunSql (Join-Path $repo 'tests/production-late-recording/writer.test.sql') 'writer.txt'
  RunSql (Join-Path $repo 'tests/production-reporting/seed.sql') 'reporting-seed.txt'
 }
 if($Upgrade){Fixtures}
 RunSql (Join-Path $PSScriptRoot 'before.sql') 'before.txt'
 RunSql $migration 'migration.txt'
 RunSql (Join-Path $PSScriptRoot 'after.sql') 'after.txt'
 if(-not $Upgrade){Fixtures}
 if($Smoke){Write-Output 'PASS: M3C migration smoke';return}
 RunSql (Join-Path $PSScriptRoot 'consumers.test.sql') 'consumers.txt'
 RunSql (Join-Path $PSScriptRoot 'periods.test.sql') 'periods.txt'
 RunSql (Join-Path $PSScriptRoot 'security.test.sql') 'security.txt'
 RunSql (Join-Path $PSScriptRoot 'performance.test.sql') 'performance.txt'
 RunSql (Join-Path $PSScriptRoot 'initiative.test.sql') 'initiative.txt'
 if($ConsumerOnly){Write-Output 'PASS: diagnostic consumer SQL path';return}
 foreach($name in @('reporting.test.sql','security.test.sql','temporal.test.sql','multiple.test.sql')){RunSql (Join-Path $repo ('tests/production-reporting/'+$name)) ('reporting-'+$name+'.txt')}
 RunSql (Join-Path $repo 'tests/production-corrections/before.sql') 'correction-before.txt'
 RunSql (Join-Path $repo 'tests/production-corrections/fixture.sql') 'correction-fixture.txt'
 foreach($name in @('policy.test.sql','security.test.sql')){RunSql (Join-Path $repo ('tests/production-corrections/'+$name)) ('correction-'+$name+'.txt')}
 foreach($name in @('boundary.test.sql','maintenance.test.sql','startup.test.sql')){RunSql (Join-Path $repo ('tests/production-late-recording/'+$name)) ('late-'+$name+'.txt')}
 foreach($spec in @(@('tests/production-corrections/concurrency.mjs','correction-races.txt'),@('tests/production-corrections/http.mjs','correction-http.txt'),@('tests/production-late-recording/concurrency.mjs','late-races.txt'),@('tests/production-consumers/concurrency.mjs','consumer-races.txt'),@('tests/production-consumers/http.mjs','consumer-http.txt'))){
  & node (Join-Path $repo $spec[0]) $bin $Port $results *> (Join-Path $results $spec[1]);if($LASTEXITCODE){throw "Failed $($spec[1])"}
 }
 RunSql (Join-Path $repo 'tests/maintenance-planning/readiness-fixture.sql') 'readiness-fixture.txt'
 foreach($name in @('recording.test.sql','readiness.test.sql','transfers.test.sql')){RunSql (Join-Path $repo ('tests/maintenance-planning/'+$name)) ('maintenance-'+$name+'.txt')}
 foreach($name in @('source-stock.test.sql','release-fixes.test.sql','high-scrap.test.sql')){RunSql (Join-Path $repo ('tests/quality/'+$name)) ('quality-'+$name+'.txt')}
 RunSql (Join-Path $PSScriptRoot 'final.sql') 'final.txt'
 foreach($file in $hashes.Keys){if((Get-FileHash -LiteralPath $file).Hash -ne $hashes[$file]){throw "Test input changed: $file"}}
 "PASS: frozen M3C local path; Upgrade=$Upgrade; no Export Reader/hosted access." | Set-Content (Join-Path $results 'summary.txt')
 Get-Content (Join-Path $results 'summary.txt')
}finally{
 if($started){& (Join-Path $bin 'pg_ctl.exe') -D $data -m fast -w stop *> (Join-Path $results 'stop.txt');if($LASTEXITCODE){throw 'Owned DB stop failed; data retained'}}
 $absolute=[IO.Path]::GetFullPath($data);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if($root.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $root -Leaf).StartsWith('FactoryLean-Consumers-M3C-') -and $absolute.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $absolute -Recurse -Force}else{throw 'Unsafe disposable cleanup path'}
}
