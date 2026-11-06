param([Parameter(Mandatory=$true)][string]$RuntimeDirectory,[int]$Port=55474,[switch]$Upgrade,[switch]$IntegratedOnly)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('FactoryLean-Acceptance-M3D-'+[guid]::NewGuid().ToString('N'))
$bin=Join-Path $RuntimeDirectory 'pgsql/bin';$data=Join-Path $root 'data';$results=Join-Path $root 'results'
if(Test-Path $root){throw 'Disposable directory already exists'}
if(@([Net.Dns]::GetHostAddresses('127.0.0.1')|Where-Object{![Net.IPAddress]::IsLoopback($_)}).Count){throw 'Nonlocal address'}
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$Port);try{$listener.Start()}finally{$listener.Stop()}
$versions=@('20261018073654_production_shift_work_v3_m1.sql','20261019063715_production_late_recording_v3_m2.sql','20261019091907_production_reporting_v3_m3a.sql','20261019114709_production_correction_approval_v1.sql','20261019124124_production_scrap_lean_consumers_v3_m3c.sql')
$all=@(Get-ChildItem (Join-Path $repo 'supabase/migrations') -File|Sort-Object Name)
$manifest=@($all|Where-Object Name -ne '20261006072000_factory_export_reader.sql')
$baseline=@($manifest|Where-Object Name -notin $versions)
if($all.Count -ne 96 -or $manifest.Count -ne 95 -or $baseline.Count -ne 90 -or (($manifest|Select-Object -Last 5 -ExpandProperty Name)-join ',') -ne ($versions-join ',')){throw 'Unexpected migration chain'}
New-Item -ItemType Directory $results|Out-Null;Write-Output "Evidence: $root"
$manifest|ForEach-Object{[ordered]@{name=$_.Name;sha256=(Get-FileHash $_.FullName).Hash}}|ConvertTo-Json|Set-Content (Join-Path $results 'migration-manifest.json')
[ordered]@{host='127.0.0.1';resolved='127.0.0.1';database='factory_lean_quality_local';port=$Port;owned_data=$data;fresh_cluster=$true;credentials='local fixture/trust only';export_reader='EXCLUDED';baseline=90;additions=$versions;upgrade=[bool]$Upgrade}|ConvertTo-Json|Set-Content (Join-Path $results 'isolation.json')
$hashes=[ordered]@{}
foreach($f in @(git -C $repo ls-files --cached --others --exclude-standard|Where-Object{$_ -match '^(src/|supabase/|tests/)' -and $_ -notmatch '^supabase/\.temp/'})){$absolute=Join-Path $repo $f;$hashes[$absolute]=(Get-FileHash $absolute).Hash}
$hashes|ConvertTo-Json|Set-Content (Join-Path $results 'input-hashes.json')
# Never inherit the real repository's hosted .env.local for any test application.
$env:NEXT_PUBLIC_SUPABASE_URL='http://127.0.0.1:1';$env:NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY='local-fixture-only';$env:APP_ORIGIN='http://127.0.0.1';$env:NEXT_TELEMETRY_DISABLED='1'
& (Join-Path $bin 'postgres.exe') --version|Set-Content (Join-Path $results 'version.txt')
& (Join-Path $bin 'initdb.exe') -D $data -U quality_fixture --encoding=UTF8 --locale=C --auth=trust *> (Join-Path $results 'initdb.txt');if($LASTEXITCODE){throw 'initdb failed'}
Add-Content (Join-Path $data 'postgresql.conf') "`nlisten_addresses='127.0.0.1'`nport=$Port`ntimezone='UTC'`n"
$started=$false
try{
 $p=Start-Process (Join-Path $bin 'pg_ctl.exe') -ArgumentList @('-D',('"'+$data+'"'),'-l',('"'+(Join-Path $root 'postgres.log')+'"'),'-w','start') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $results 'start.txt') -RedirectStandardError (Join-Path $results 'start-error.txt')
 if(!$p.WaitForExit(30000) -or $p.ExitCode){throw 'start failed'};$started=$true
 & (Join-Path $bin 'createdb.exe') -h 127.0.0.1 -p $Port -U quality_fixture factory_lean_quality_local;if($LASTEXITCODE){throw 'createdb failed'}
 function RunSql([string]$relative,[string]$name){
  $file=if([IO.Path]::IsPathRooted($relative)){$relative}else{Join-Path $repo $relative};$prior=$ErrorActionPreference
  try{$ErrorActionPreference='Continue';& (Join-Path $bin 'psql.exe') -X -h 127.0.0.1 -p $Port -U quality_fixture -d factory_lean_quality_local -v ON_ERROR_STOP=1 -f $file *> (Join-Path $results $name);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$prior}
  if($code){throw "SQL failed: $name"}
 }
 function RunNode([string]$relative,[string]$name,[string]$destination=$results){
  & node (Join-Path $repo $relative) $bin $Port $destination *> (Join-Path $results $name);if($LASTEXITCODE){throw "Node integration failed: $name"}
 }
 RunSql 'tests/quality/local-bootstrap.sql' 'bootstrap.txt'
 $includes=$baseline|ForEach-Object{if($_.Name -eq '20261010061827_quality_source_stock_v1.sql'){"\i '"+(Join-Path $repo 'tests/quality/pre-source-fixture.sql').Replace('\','/')+"'"};"\i '"+$_.FullName.Replace('\','/')+"'"}
 $includes|Set-Content (Join-Path $root 'baseline.sql');RunSql (Join-Path $root 'baseline.sql') 'baseline.txt'
 RunSql 'tests/production-acceptance/before.sql' 'acceptance-before.txt'
 RunSql 'tests/maintenance-planning/fixture.sql' 'mp-fixture.txt'
 if($Upgrade){RunSql 'tests/production-shift-work/before.sql' 'm1-before.txt';RunSql 'tests/production-acceptance/upgrade-before.sql' 'upgrade-before.txt'}
 RunSql ('supabase/migrations/'+$versions[0]) 'm1.txt'
 if(!$Upgrade){RunSql 'tests/production-shift-work/before.sql' 'm1-before.txt'}
 $mode=if($Upgrade){'upgrade'}else{'fresh'}
 ("set shift_test.install_mode='$mode';`n\i '"+(Join-Path $repo 'tests/production-shift-work/after.sql').Replace('\','/')+"'")|Set-Content (Join-Path $root 'm1-after.sql');RunSql (Join-Path $root 'm1-after.sql') 'm1-after.txt'
 foreach($name in $versions[1..3]){RunSql ('supabase/migrations/'+$name) $name.Replace('.sql','.txt')}
 RunSql 'tests/production-consumers/before.sql' 'm3c-before.txt'
 RunSql ('supabase/migrations/'+$versions[4]) 'm3c.txt'
 RunSql 'tests/production-consumers/after.sql' 'm3c-after.txt'
 if($Upgrade){RunSql 'tests/production-acceptance/upgrade-after.sql' 'upgrade-after.txt'}
 if(!$IntegratedOnly){
  RunSql 'tests/production-shift-work/temporal.test.sql' 'm1-temporal.txt'
  RunSql 'tests/production-shift-work/reader.test.sql' 'm1-reader.txt'
  $m1Out=Join-Path $results 'FactoryLean-Shift-M1-evidence';New-Item -ItemType Directory $m1Out|Out-Null
  RunNode 'tests/production-shift-work/api-integration.mjs' 'm1-http.txt' $m1Out
  RunNode 'tests/production-shift-work/concurrency.mjs' 'm1-races.txt' $m1Out
 }
 RunSql 'tests/production-late-recording/fixture.sql' 'm2-fixture.txt'
 RunSql 'tests/production-late-recording/writer.test.sql' 'm2-writer.txt'
 RunSql 'tests/production-reporting/seed.sql' 'reporting-seed.txt'
 foreach($name in @('consumers.test.sql','periods.test.sql','security.test.sql','performance.test.sql','initiative.test.sql')){RunSql ('tests/production-consumers/'+$name) ('consumer-'+$name+'.txt')}
 if(!$IntegratedOnly){
  foreach($name in @('reporting.test.sql','security.test.sql','temporal.test.sql','multiple.test.sql','performance.test.sql')){RunSql ('tests/production-reporting/'+$name) ('reporting-'+$name+'.txt')}
  RunNode 'tests/production-reporting/http.mjs' 'reporting-http.txt'
  RunSql 'tests/production-corrections/before.sql' 'correction-before.txt'
  RunSql 'tests/production-corrections/fixture.sql' 'correction-fixture.txt'
  foreach($name in @('policy.test.sql','security.test.sql')){RunSql ('tests/production-corrections/'+$name) ('correction-'+$name+'.txt')}
  # The historical replay suite is specifically pre-policy, not a replay of
  # current auto-approved request UUIDs created by the preceding regressions.
  if($Upgrade){
   "delete from correction_test.historical where id not in(select (x->>'correction')::uuid from acceptance_test.legacy);"|Set-Content (Join-Path $root 'historical-scope.sql')
   RunSql (Join-Path $root 'historical-scope.sql') 'historical-scope.txt'
   RunSql 'tests/production-corrections/historical.test.sql' 'correction-historical.test.sql.txt'
  }else{'NOT APPLICABLE: pre-policy replay requires the upgrade fixture.'|Set-Content (Join-Path $results 'correction-historical.test.sql.txt')}
  RunNode 'tests/production-corrections/concurrency.mjs' 'correction-races.txt'
  RunNode 'tests/production-corrections/http.mjs' 'correction-http.txt'
  foreach($name in @('boundary.test.sql','maintenance.test.sql','startup.test.sql')){RunSql ('tests/production-late-recording/'+$name) ('late-'+$name+'.txt')}
  RunNode 'tests/production-late-recording/http.mjs' 'late-http.txt'
  RunNode 'tests/production-late-recording/concurrency.mjs' 'late-races.txt'
  RunNode 'tests/production-consumers/concurrency.mjs' 'consumer-races.txt'
  RunNode 'tests/production-consumers/http.mjs' 'consumer-http.txt'
  RunSql 'tests/maintenance-planning/readiness-fixture.sql' 'readiness-fixture.txt'
  foreach($name in @('recording.test.sql','readiness.test.sql','transfers.test.sql','loss.test.sql')){RunSql ('tests/maintenance-planning/'+$name) ('maintenance-'+$name+'.txt')}
  foreach($name in @('source-stock.test.sql','release-fixes.test.sql','high-scrap.test.sql')){RunSql ('tests/quality/'+$name) ('quality-'+$name+'.txt')}
  RunSql 'tests/production-acceptance/platform-fixture.sql' 'platform-fixture.txt'
  foreach($name in @('supply-flow.test.sql','warehouse-manual-purchase.test.sql','purchasing-suppliers.test.sql','purchase-requester.test.sql','production-execution.test.sql','downtime-capture.test.sql')){RunSql ('tests/'+$name) ('platform-'+$name+'.txt')}
 }
 RunNode 'tests/production-acceptance/integrated.mjs' 'integrated.txt'
 if($IntegratedOnly){
  # The full M2 concurrency suite performs this cleanup itself. Diagnostic-only
  # fixtures must also undo the writer suite's temporary schema3 readiness.
  'update private.production_recording_v3_activation set enabled=false,schema_contract_version=0;'|Set-Content (Join-Path $root 'diagnostic-gate-cleanup.sql')
  RunSql (Join-Path $root 'diagnostic-gate-cleanup.sql') 'diagnostic-gate-cleanup.txt'
 }
 RunSql 'tests/production-consumers/final.sql' 'consumer-final.txt'
 RunSql 'tests/production-acceptance/final.sql' 'acceptance-final.txt'
 foreach($file in $hashes.Keys){if((Get-FileHash -LiteralPath $file).Hash -ne $hashes[$file]){throw "Input changed: $file"}}
 "PASS: Phase3D $mode; IntegratedOnly=$IntegratedOnly; 90 pre-V3 +5 ordered V3 migrations; no Export Reader/hosted access."|Set-Content (Join-Path $results 'summary.txt');Get-Content (Join-Path $results 'summary.txt')
}finally{
 if($started){& (Join-Path $bin 'pg_ctl.exe') -D $data -m fast -w stop *> (Join-Path $results 'stop.txt');if($LASTEXITCODE){throw 'Owned DB failed to stop; data retained'}}
 $absolute=[IO.Path]::GetFullPath($data);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if($root.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $root -Leaf).StartsWith('FactoryLean-Acceptance-M3D-') -and $absolute.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $absolute -Recurse -Force}else{throw 'Unsafe disposable cleanup path'}
}
