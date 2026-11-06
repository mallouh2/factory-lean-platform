param([Parameter(Mandatory=$true)][string]$RuntimeDirectory,[int]$Port=55460,[switch]$Upgrade)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('FactoryLean-Shift-M1-'+[guid]::NewGuid().ToString('N'))
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
 # Both paths validate the authorized release chain, never the deferred Export Reader.
 $migrations=Get-ChildItem (Join-Path $repo 'supabase/migrations') -File | Where-Object Name -ne '20261006072000_factory_export_reader.sql' | Sort-Object Name
 $baseline=$migrations | Where-Object Name -ne '20261018073654_production_shift_work_v3_m1.sql'
 $includes=$baseline | ForEach-Object {"\i '"+$_.FullName.Replace('\','/').Replace("'","''")+"'"}
 $includes | Set-Content (Join-Path $root 'baseline.sql')
 RunSql (Join-Path $root 'baseline.sql') 'baseline.txt'
 RunSql (Join-Path $PSScriptRoot 'compatibility-before.sql') 'compatibility-before.txt'
 if(-not $Upgrade){RunSql (Join-Path $repo 'supabase/migrations/20261018073654_production_shift_work_v3_m1.sql') 'm1.txt'}
 RunSql (Join-Path $repo 'tests/maintenance-planning/fixture.sql') 'fixture.txt'
 RunSql (Join-Path $PSScriptRoot 'before.sql') 'before.txt'
 if($Upgrade){RunSql (Join-Path $repo 'supabase/migrations/20261018073654_production_shift_work_v3_m1.sql') 'm1.txt'}
 RunSql (Join-Path $PSScriptRoot 'compatibility-after.sql') 'compatibility-after.txt'
 $mode=if($Upgrade){'upgrade'}else{'fresh'}
 ("set shift_test.install_mode='"+$mode+"';`n\i '"+(Join-Path $PSScriptRoot 'after.sql').Replace('\','/').Replace("'","''")+"'") | Set-Content (Join-Path $root 'after.sql')
 RunSql (Join-Path $root 'after.sql') 'after.txt'
 RunSql (Join-Path $PSScriptRoot 'temporal.test.sql') 'temporal.txt'
 RunSql (Join-Path $PSScriptRoot 'reader.test.sql') 'reader.txt'
 $legacy=[IO.File]::ReadAllText((Join-Path $repo 'tests/shift-time-windows.test.sql')).Replace("'bab9b5da-d78d-4be7-b6d4-bb6afc388c3a'","(select (x->>'factory')::uuid from shift_test.baseline)").Replace("'d699a3ac-fab0-4faf-b958-f3902bc357ba'","(select (x->>'owner')::uuid from shift_test.baseline)")
 $legacy="update public.factories set timezone='Asia/Qatar' where id=(select (x->>'factory')::uuid from shift_test.baseline);`n"+$legacy
 [IO.File]::WriteAllText((Join-Path $root 'legacy-shifts.sql'),$legacy)
 RunSql (Join-Path $root 'legacy-shifts.sql') 'legacy-shifts.txt'
 RunSql (Join-Path $repo 'tests/maintenance-planning/readiness-fixture.sql') 'readiness-fixture.txt'
 RunSql (Join-Path $repo 'tests/maintenance-planning/recording.test.sql') 'wip-recording.txt'
 RunSql (Join-Path $repo 'tests/quality/pre-source-fixture.sql') 'readiness-stock-fixture.txt'
 RunSql (Join-Path $repo 'tests/maintenance-planning/readiness.test.sql') 'readiness.txt'
 RunSql (Join-Path $repo 'tests/maintenance-planning/transfers.test.sql') 'transfers.txt'
 $executionPrelude="update public.factories set is_demo=true where id=(select (x->>'factory')::uuid from shift_test.baseline);"
 $executionPrelude | Set-Content (Join-Path $root 'execution-prelude.sql')
 RunSql (Join-Path $root 'execution-prelude.sql') 'execution-prelude.txt'
 RunSql (Join-Path $repo 'tests/production-execution.test.sql') 'execution.txt'
 & node (Join-Path $PSScriptRoot 'api-integration.mjs') $bin $Port $results *> (Join-Path $results 'api-integration.txt')
 if($LASTEXITCODE){throw 'Local HTTP/SQL integration failed'}
 & node (Join-Path $PSScriptRoot 'concurrency.mjs') $bin $Port $results *> (Join-Path $results 'concurrency.txt')
 if($LASTEXITCODE){throw 'Concurrency tests failed'}
 foreach($f in $inputHashes.Keys){if((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash -ne $inputHashes[$f]){throw "Test input changed during execution: $f"}}
 "PASS: $mode baseline $(@($baseline).Count), M1, unchanged worker contracts, temporal, reader/keyset plans, legacy shifts, WIP, readiness, transfers, execution, HTTP/SQL, concurrency. Export Reader excluded. Standalone PostgreSQL/session adapter, not GoTrue/PostgREST." | Set-Content (Join-Path $results 'summary.txt')
 Get-Content (Join-Path $results 'summary.txt')
}finally{
 if($started){
  & (Join-Path $bin 'pg_ctl.exe') -D $data -m fast -w stop *> (Join-Path $results 'stop.txt')
  if($LASTEXITCODE){throw 'Failed to stop owned PostgreSQL; data retained'}
 }
 $resolved=[IO.Path]::GetFullPath($data)
 $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if($root.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $root -Leaf).StartsWith('FactoryLean-Shift-M1-') -and $resolved.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
  Remove-Item -LiteralPath $resolved -Recurse -Force
 }else{throw 'Unexpected disposable data path; deletion refused'}
}
