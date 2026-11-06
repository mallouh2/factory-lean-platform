param([string]$RuntimeDirectory='C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-Runtime-20261018')
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$priorRoot=Get-Content (Join-Path $env:TEMP 'FactoryLean-Output-P4D-Preview-location.txt')
$prior=Get-Content (Join-Path $priorRoot 'runtime.json') -Raw|ConvertFrom-Json
if($prior.marker -ne 'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY' -or -not (Test-Path (Join-Path $prior.app '.next/BUILD_ID'))){throw 'Verified local build required'}
foreach($file in Get-ChildItem (Join-Path $repo 'src') -Recurse -File){$relative=$file.FullName.Substring($repo.Length+1);if((Get-FileHash $file.FullName).Hash -ne (Get-FileHash (Join-Path $prior.app $relative)).Hash){throw "Source differs from verified build: $relative"}}
foreach($port in @(55495,4303,4221)){$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$port);try{$listener.Start()}finally{$listener.Stop()}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('FactoryLean-Output-P4E-Preview-'+[guid]::NewGuid().ToString('N'));$app=Join-Path $root 'app';$bin=Join-Path $RuntimeDirectory 'pgsql/bin';$data=Join-Path $root 'data'
New-Item -ItemType Directory $app|Out-Null
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $root /inheritance:r /grant:r "*${sid}:(OI)(CI)F"|Out-Null;if($LASTEXITCODE){throw 'Owner ACL failed'}
Set-Content (Join-Path $env:TEMP 'FactoryLean-Output-P4E-Preview-location.txt') $root
& robocopy.exe $prior.app $app /E /XD node_modules (Join-Path $prior.app '.next/cache') (Join-Path $prior.app '.next/standalone') /XF .env.local tsconfig.tsbuildinfo /NFL /NDL /NJH /NJS /NP *> (Join-Path $root 'copy-build.txt')
if($LASTEXITCODE -gt 7){throw 'Isolated build copy failed'}
New-Item -ItemType Junction -Path (Join-Path $app 'node_modules') -Target (Join-Path $repo 'node_modules')|Out-Null
@'
APP_ENV=local
APP_ORIGIN=http://127.0.0.1:4221
SUPABASE_URL=http://127.0.0.1:4303
SUPABASE_PUBLISHABLE_KEY=local-preview-public-not-a-hosted-key
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:4303
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=local-preview-public-not-a-hosted-key
NEXT_TELEMETRY_DISABLED=1
'@|Set-Content (Join-Path $app '.env.local')
& (Join-Path $bin 'initdb.exe') -D $data -U quality_fixture --encoding=UTF8 --locale=C --auth=trust *> (Join-Path $root 'initdb.txt');if($LASTEXITCODE){throw 'initdb failed'}
Add-Content (Join-Path $data 'postgresql.conf') "`nlisten_addresses='127.0.0.1'`nport=55495`ntimezone='UTC'`n"
$p=Start-Process (Join-Path $bin 'pg_ctl.exe') -ArgumentList @('-D',('"'+$data+'"'),'-l',('"'+(Join-Path $root 'postgres.log')+'"'),'-w','start') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'start.txt') -RedirectStandardError (Join-Path $root 'start-error.txt')
if(!$p.WaitForExit(30000) -or $p.ExitCode){throw 'Owned PostgreSQL start failed'}
& (Join-Path $bin 'createdb.exe') -h 127.0.0.1 -p 55495 -U quality_fixture factory_lean_quality_local;if($LASTEXITCODE){throw 'createdb failed'}
function RunSql([string]$file,[string]$log){$priorPreference=$ErrorActionPreference;try{$ErrorActionPreference='Continue';& (Join-Path $bin 'psql.exe') -X -h 127.0.0.1 -p 55495 -U quality_fixture -d factory_lean_quality_local -v ON_ERROR_STOP=1 -f $file *> (Join-Path $root $log);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$priorPreference};if($code){throw "SQL setup failed: $log; evidence retained $root"}}
@'
select jsonb_build_object('address',inet_server_addr(),'port',inet_server_port(),'database',current_database(),'data_directory',current_setting('data_directory'),'server_version',current_setting('server_version'));
do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55495 or current_database()<>'factory_lean_quality_local' then raise exception 'Not disposable loopback';end if;end$$;
'@|Set-Content (Join-Path $root 'endpoint.sql');RunSql (Join-Path $root 'endpoint.sql') 'endpoint-proof.txt'
RunSql (Join-Path $repo 'tests/quality/local-bootstrap.sql') 'bootstrap.txt'
$migrations=@(Get-ChildItem (Join-Path $repo 'supabase/migrations') -Filter '*.sql'|Where-Object Name -ne '20261006072000_factory_export_reader.sql'|Sort-Object Name)
if($migrations.Count -ne 111){throw 'Unexpected executable migration chain'}
$includes=$migrations|ForEach-Object{if($_.Name -eq '20261010061827_quality_source_stock_v1.sql'){"\i '"+(Join-Path $repo 'tests/quality/pre-source-fixture.sql').Replace('\','/')+"'"};"\i '"+$_.FullName.Replace('\','/')+"'"}
$includes|Set-Content (Join-Path $root 'chain.sql');RunSql (Join-Path $root 'chain.sql') 'migrations.txt'
@'
do $$begin if private.manufactured_output_enabled(gen_random_uuid()) or exists(select 1 from private.production_recording_v3_activation where enabled or schema_contract_version<>0) then raise exception 'Shipped gates changed';end if;end$$;
'@|Set-Content (Join-Path $root 'inactive.sql');RunSql (Join-Path $root 'inactive.sql') 'inactive.txt'
RunSql (Join-Path $repo 'tests/maintenance-planning/fixture.sql') 'base-fixture.txt'
RunSql (Join-Path $repo 'tests/production-late-recording/fixture.sql') 'shift-fixture.txt'
RunSql (Join-Path $repo 'tests/manufactured-output-phase2/fixture.sql') 'local-predicate-fixture.txt'
RunSql (Join-Path $PSScriptRoot 'fixture.sql') 'acceptance-fixture.txt'
$contexts=& (Join-Path $bin 'psql.exe') -X -qAt -h 127.0.0.1 -p 55495 -U quality_fixture -d factory_lean_quality_local -c 'select jsonb_object_agg(name,x) from output4e_test.contexts'
if($LASTEXITCODE){throw 'Fixture contexts unavailable'};$c=$contexts|ConvertFrom-Json
[ordered]@{marker='FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY';root=$root;repo=$repo;app=$app;bin=$bin;database='factory_lean_quality_local';databaseHost='127.0.0.1';databasePort=55495;backendPort=4303;applicationPort=4221;context=$c.A;additionalContexts=@($c.C);scenarios=$c;verifiedBuild=$prior.app;gates='Shipped FALSE; existing disposable predicate fixture only'}|ConvertTo-Json -Depth 12|Set-Content (Join-Path $root 'runtime.json')
$backend=Start-Process node -ArgumentList @((Join-Path $repo 'tests/production-recording-full-app/backend.mjs'),(Join-Path $root 'runtime.json')) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'backend.txt') -RedirectStandardError (Join-Path $root 'backend-error.txt')
$web=Start-Process node -WorkingDirectory $app -ArgumentList @((Join-Path $repo 'node_modules/next/dist/bin/next'),'start','-H','127.0.0.1','-p','4221') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'web.txt') -RedirectStandardError (Join-Path $root 'web-error.txt')
@{backend=$backend.Id;web=$web.Id}|ConvertTo-Json|Set-Content (Join-Path $root 'processes.json')
Write-Output "Fresh local acceptance preview: http://127.0.0.1:4221/ ($root)"
