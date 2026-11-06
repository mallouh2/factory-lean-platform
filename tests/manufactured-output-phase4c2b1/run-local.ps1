param([Parameter(Mandatory=$true)][string]$RuntimeDirectory,[int]$Port=55491)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('FactoryLean-Output-P4C2B1-SQL-'+[guid]::NewGuid().ToString('N'))
$bin=Join-Path $RuntimeDirectory 'pgsql/bin';$data=Join-Path $root 'data';$results=Join-Path $root 'results'
New-Item -ItemType Directory -Path $results | Out-Null
Write-Output "Evidence: $root"
Set-Content (Join-Path ([IO.Path]::GetTempPath()) 'FactoryLean-Output-P4C2B1-SQL-location.txt') $root
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$Port)
try{$listener.Start()}finally{$listener.Stop()}
& (Join-Path $bin 'initdb.exe') -D $data -U quality_fixture --encoding=UTF8 --locale=C --auth=trust *> (Join-Path $results 'initdb.txt')
if($LASTEXITCODE){throw 'initdb failed'}
Add-Content (Join-Path $data 'postgresql.conf') "`nlisten_addresses='127.0.0.1'`nport=$Port`ntimezone='UTC'`n"
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
 $migration=Join-Path $repo 'supabase/migrations/20261026063417_manufactured_output_safe_reconciliation_v4c2b1.sql'
 $baseline=@(Get-ChildItem (Join-Path $repo 'supabase/migrations') -Filter '*.sql' | Where-Object {$_.Name -ne '20261006072000_factory_export_reader.sql' -and $_.FullName -ne $migration} | Sort-Object Name)
 if($baseline.Count -ne 107){throw 'Unexpected baseline'}
 $hashes=[ordered]@{}
 foreach($file in @($baseline)+(Get-Item $migration)+@(Get-ChildItem $PSScriptRoot -File)){$hashes[$file.FullName]=(Get-FileHash $file.FullName).Hash}
 $hashes | ConvertTo-Json | Set-Content (Join-Path $results 'input-hashes.json')
 $includes=$baseline | ForEach-Object{if($_.Name -eq '20261010061827_quality_source_stock_v1.sql'){"\i '"+(Join-Path $repo 'tests/quality/pre-source-fixture.sql').Replace('\','/')+"'"};"\i '"+$_.FullName.Replace('\','/')+"'"}
 $includes | Set-Content (Join-Path $root 'baseline.sql');RunSql (Join-Path $root 'baseline.sql') 'baseline.txt'

 "select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('private','public') and p.proname in ('warehouse_inventory_rows','finished_source_stock','warehouse_page','fulfillment_preview','sales_fulfillment','warehouse_fulfillment');" | Set-Content (Join-Path $root 'contracts.sql')
 RunSql (Join-Path $root 'contracts.sql') 'contracts.txt'
 RunSql $migration 'migration.txt'
 @'
do $$begin
 if private.manufactured_output_enabled(gen_random_uuid()) or exists(select 1 from private.production_recording_v3_activation where enabled or schema_contract_version<>0) then raise exception 'Activation changed';end if;
 if has_function_privilege('anon','public.record_manufactured_output(uuid,jsonb,uuid)','execute') or not has_function_privilege('authenticated','public.record_manufactured_output(uuid,jsonb,uuid)','execute') or has_table_privilege('authenticated','private.manufactured_outputs','insert') then raise exception 'Protected grants changed';end if;
end$$;
'@ | Set-Content (Join-Path $root 'inactive-grants.sql')
 RunSql (Join-Path $root 'inactive-grants.sql') 'inactive-grants.txt'

 RunSql (Join-Path $repo 'tests/maintenance-planning/fixture.sql') 'fixture-base.txt'
 RunSql (Join-Path $repo 'tests/production-late-recording/fixture.sql') 'late-fixture.txt'
 RunSql (Join-Path $repo 'tests/manufactured-output-phase2/fixture.sql') 'fixture.txt'
 @('begin;',("\i '"+(Join-Path $repo 'tests/manufactured-output-phase2/integration.test.sql').Replace('\','/')+"'"),'rollback;') | Set-Content (Join-Path $root 'phase2-regression.sql')
 RunSql (Join-Path $root 'phase2-regression.sql') 'phase2-regression.txt'
 RunSql (Join-Path $repo 'tests/manufactured-output-phase4/integration.test.sql') 'phase4-integration.txt'
 RunSql (Join-Path $repo 'tests/manufactured-output-phase4/fixture.sql') 'phase4-fixture.txt'
 RunSql (Join-Path $repo 'tests/manufactured-output-phase4/scenarios.test.sql') 'phase4-scenarios.txt'
 RunSql (Join-Path $repo 'tests/manufactured-output-phase4/allocations.test.sql') 'phase4-sales.txt'
 RunSql (Join-Path $repo 'tests/manufactured-output-phase4a/integration.test.sql') 'all-scrap-regression.txt'
 RunSql (Join-Path $repo 'tests/manufactured-output-phase4b/integration.test.sql') 'revision-regression.txt'
 RunSql (Join-Path $repo 'tests/manufactured-output-phase4b/guards.test.sql') 'revision-guards-regression.txt'
 RunSql (Join-Path $repo 'tests/manufactured-output-phase4c2a/integration.test.sql') 'findings-regression.txt'
 RunSql (Join-Path $PSScriptRoot 'integration.test.sql') 'reconciliation.txt'
 & node (Join-Path $PSScriptRoot 'concurrency.mjs') $bin $Port $results *> (Join-Path $results 'concurrency.txt')
 if($LASTEXITCODE){throw 'Concurrency failed'}
 foreach($file in $hashes.Keys){if((Get-FileHash -LiteralPath $file).Hash -ne $hashes[$file]){throw "Test input changed: $file"}}
 'PASS: inactive Phase4C2B1 safe reconciliation; local SQL only.' | Set-Content (Join-Path $results 'summary.txt')
 Get-Content (Join-Path $results 'summary.txt')
}finally{
 if($started){& (Join-Path $bin 'pg_ctl.exe') -D $data -m fast -w stop *> (Join-Path $results 'stop.txt');if($LASTEXITCODE){throw 'Owned DB stop failed'}}
 $absolute=[IO.Path]::GetFullPath($data);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if($root.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $root -Leaf).StartsWith('FactoryLean-Output-P4C2B1-SQL-') -and $absolute.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $absolute -Recurse -Force}else{throw 'Unsafe cleanup'}
}
