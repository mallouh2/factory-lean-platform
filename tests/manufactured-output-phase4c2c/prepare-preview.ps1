param([string]$RuntimeDirectory='C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-Runtime-20261018')
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('FactoryLean-Output-P4C2C-Preview-'+[guid]::NewGuid().ToString('N'))
$app=Join-Path $root 'app';$bin=Join-Path $RuntimeDirectory 'pgsql/bin';$data=Join-Path $root 'data'
foreach($port in @(55493,4301,4219)){$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$port);try{$listener.Start()}finally{$listener.Stop()}}
New-Item -ItemType Directory $app | Out-Null
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $root /inheritance:r /grant:r "*${sid}:(OI)(CI)F" | Out-Null
if($LASTEXITCODE){throw 'Owner ACL failed'}
Set-Content (Join-Path $env:TEMP 'FactoryLean-Output-P4C2C-Preview-location.txt') $root
foreach($dir in @('src','public','scripts')){Copy-Item -LiteralPath (Join-Path $repo $dir) -Destination $app -Recurse}
foreach($file in @('package.json','package-lock.json','tsconfig.json','next-env.d.ts','next.config.ts','next.config.mjs','next.config.js')){if(Test-Path (Join-Path $repo $file)){Copy-Item -LiteralPath (Join-Path $repo $file) -Destination $app}}
New-Item -ItemType Junction -Path (Join-Path $app 'node_modules') -Target (Join-Path $repo 'node_modules') | Out-Null
@'
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:4301
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=local-preview-public-not-a-hosted-key
SUPABASE_URL=http://127.0.0.1:4301
SUPABASE_PUBLISHABLE_KEY=local-preview-public-not-a-hosted-key
APP_ENV=local
APP_ORIGIN=http://127.0.0.1:4219
NEXT_TELEMETRY_DISABLED=1
'@ | Set-Content (Join-Path $app '.env.local')
Write-Output "Isolated preview/build: $root"
Push-Location $app
try{& node (Join-Path $repo 'node_modules/typescript/bin/tsc') --noEmit --incremental false *> (Join-Path $root 'typescript.txt');if($LASTEXITCODE){throw 'TypeScript failed'}
 & node (Join-Path $repo 'node_modules/next/dist/bin/next') build --webpack *> (Join-Path $root 'build.txt');if($LASTEXITCODE){throw 'Build failed'}
}finally{Pop-Location}
& (Join-Path $bin 'initdb.exe') -D $data -U quality_fixture --encoding=UTF8 --locale=C --auth=trust *> (Join-Path $root 'initdb.txt');if($LASTEXITCODE){throw 'initdb failed'}
Add-Content (Join-Path $data 'postgresql.conf') "`nlisten_addresses='127.0.0.1'`nport=55493`ntimezone='UTC'`n"
$p=Start-Process (Join-Path $bin 'pg_ctl.exe') -ArgumentList @('-D',('"'+$data+'"'),'-l',('"'+(Join-Path $root 'postgres.log')+'"'),'-w','start') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'start.txt') -RedirectStandardError (Join-Path $root 'start-error.txt')
if(!$p.WaitForExit(30000) -or $p.ExitCode){throw 'PostgreSQL start failed'}
& (Join-Path $bin 'createdb.exe') -h 127.0.0.1 -p 55493 -U quality_fixture factory_lean_quality_local
if($LASTEXITCODE){throw 'createdb failed'}
function RunSql([string]$file,[string]$log){$prior=$ErrorActionPreference;try{$ErrorActionPreference='Continue';& (Join-Path $bin 'psql.exe') -X -h 127.0.0.1 -p 55493 -U quality_fixture -d factory_lean_quality_local -v ON_ERROR_STOP=1 -f $file *> (Join-Path $root $log);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$prior};if($code){throw "SQL failed: $log; owned local fixture retained at $root"}}
RunSql (Join-Path $repo 'tests/quality/local-bootstrap.sql') 'bootstrap.txt'
$migrations=@(Get-ChildItem (Join-Path $repo 'supabase/migrations') -Filter '*.sql' | Where-Object Name -ne '20261006072000_factory_export_reader.sql' | Sort-Object Name)
if($migrations.Count -ne 110){throw 'Unexpected migration count'}
$includes=$migrations | ForEach-Object{if($_.Name -eq '20261010061827_quality_source_stock_v1.sql'){"\i '"+(Join-Path $repo 'tests/quality/pre-source-fixture.sql').Replace('\','/')+"'"};"\i '"+$_.FullName.Replace('\','/')+"'"}
$includes | Set-Content (Join-Path $root 'chain.sql');RunSql (Join-Path $root 'chain.sql') 'migrations.txt'
@'
do $$begin if private.manufactured_output_enabled(gen_random_uuid()) or exists(select 1 from private.production_recording_v3_activation where enabled or schema_contract_version<>0) then raise exception 'Shipped gate changed';end if;end$$;
'@ | Set-Content (Join-Path $root 'inactive.sql');RunSql (Join-Path $root 'inactive.sql') 'inactive.txt'
RunSql (Join-Path $repo 'tests/maintenance-planning/fixture.sql') 'existing-fixture.txt'
RunSql (Join-Path $repo 'tests/production-late-recording/fixture.sql') 'late-fixture.txt'
RunSql (Join-Path $repo 'tests/manufactured-output-phase2/fixture.sql') 'seed.txt'
$fixture=(Get-Content (Join-Path $repo 'tests/manufactured-output-phase4/fixture.sql') -Raw).Replace('not in (55490,55491)','<>55493')
$fixture | Set-Content (Join-Path $root 'completion-fixture.sql');RunSql (Join-Path $root 'completion-fixture.sql') 'completion-fixture.txt'
# Load existing deterministic helper definitions only; do not repeat earlier suites.
foreach($phase in @('4b','4c2a','4c2b1','4c2b2')){
 $text=Get-Content (Join-Path $repo "tests/manufactured-output-phase$phase/integration.test.sql") -Raw
 $text=($text -split '(?m)^begin;\r?$',2)[0];$text=$text.Replace('<>55491','<>55493')
 $path=Join-Path $root "helpers-$phase.sql";$text | Set-Content $path;RunSql $path "helpers-$phase.txt"
}
RunSql (Join-Path $PSScriptRoot 'integration.test.sql') 'reader-tests.txt'
@'
do $$declare x jsonb;begin
 x:=output4_test.context('Quality integration manual');
 perform output4_test.decision(x,'COMPLETE',10);perform output4c_test.identify(x);
 create table public.local_reconciliation_fixture(context jsonb);insert into public.local_reconciliation_fixture values(x);
end$$;
select context from public.local_reconciliation_fixture;
'@ | Set-Content (Join-Path $root 'context.sql')
RunSql (Join-Path $root 'context.sql') 'context.txt'
$context=& (Join-Path $bin 'psql.exe') -X -qAt -h 127.0.0.1 -p 55493 -U quality_fixture -d factory_lean_quality_local -c 'select context from public.local_reconciliation_fixture'
if($LASTEXITCODE){throw 'Context unavailable'}
[ordered]@{marker='FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY';root=$root;repo=$repo;app=$app;bin=$bin;database='factory_lean_quality_local';databaseHost='127.0.0.1';databasePort=55493;backendPort=4301;applicationPort=4219;context=($context|ConvertFrom-Json);gates='Shipped FALSE; disposable fixture predicate only'}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $root 'runtime.json')
$backend=Start-Process node -ArgumentList @((Join-Path $repo 'tests/production-recording-full-app/backend.mjs'),(Join-Path $root 'runtime.json')) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'backend.txt') -RedirectStandardError (Join-Path $root 'backend-error.txt')
$web=Start-Process node -WorkingDirectory $app -ArgumentList @((Join-Path $repo 'node_modules/next/dist/bin/next'),'start','-H','127.0.0.1','-p','4219') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'web.txt') -RedirectStandardError (Join-Path $root 'web-error.txt')
@{backend=$backend.Id;web=$web.Id}|ConvertTo-Json|Set-Content (Join-Path $root 'processes.json')
Write-Output 'Local preview: http://127.0.0.1:4219/'
