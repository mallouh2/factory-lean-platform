param()
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root=(Get-Content (Join-Path $env:TEMP 'FactoryLean-Planning-V3-location.txt')).Trim()
if(!(Test-Path (Join-Path $root 'before-files.json')) -or !$root.StartsWith([IO.Path]::GetTempPath())){throw 'Owned isolated root required'}
$app=Join-Path $root 'app';$bin='C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-Runtime-20261018\pgsql\bin';$data=Join-Path $root 'data'
foreach($port in @(55496,4304,4222)){$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$port);try{$listener.Start()}finally{$listener.Stop()}}
New-Item -ItemType Directory $app|Out-Null
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $root /inheritance:r /grant:r "*${sid}:(OI)(CI)F"|Out-Null
if($LASTEXITCODE){throw 'Owner ACL failed'}
foreach($dir in @('src','public','scripts')){Copy-Item -LiteralPath (Join-Path $repo $dir) -Destination $app -Recurse}
foreach($file in @('package.json','package-lock.json','tsconfig.json','next-env.d.ts','next.config.ts','next.config.mjs','next.config.js')){if(Test-Path (Join-Path $repo $file)){Copy-Item -LiteralPath (Join-Path $repo $file) -Destination $app}}
New-Item -ItemType Junction -Path (Join-Path $app 'node_modules') -Target (Join-Path $repo 'node_modules')|Out-Null
@'
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:4304
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=local-preview-public-not-a-hosted-key
SUPABASE_URL=http://127.0.0.1:4304
SUPABASE_PUBLISHABLE_KEY=local-preview-public-not-a-hosted-key
APP_ENV=local
APP_ORIGIN=http://127.0.0.1:4222
NEXT_TELEMETRY_DISABLED=1
'@ | Set-Content (Join-Path $app '.env.local')
Push-Location $app
try{& node (Join-Path $repo 'node_modules/typescript/bin/tsc') --noEmit --incremental false *> (Join-Path $root 'typescript.txt');if($LASTEXITCODE){throw 'TypeScript failed'}
& node (Join-Path $repo 'node_modules/next/dist/bin/next') build --webpack *> (Join-Path $root 'build.txt');if($LASTEXITCODE){throw 'Build failed'}}finally{Pop-Location}
& (Join-Path $bin 'initdb.exe') -D $data -U quality_fixture --encoding=UTF8 --locale=C --auth=trust *> (Join-Path $root 'initdb.txt');if($LASTEXITCODE){throw 'initdb failed'}
Add-Content (Join-Path $data 'postgresql.conf') "`nlisten_addresses='127.0.0.1'`nport=55496`ntimezone='UTC'`n"
$p=Start-Process (Join-Path $bin 'pg_ctl.exe') -ArgumentList @('-D',('"'+$data+'"'),'-l',('"'+(Join-Path $root 'postgres.log')+'"'),'-w','start') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'start.txt') -RedirectStandardError (Join-Path $root 'start-error.txt')
if(!$p.WaitForExit(30000) -or $p.ExitCode){throw 'PostgreSQL start failed'}
& (Join-Path $bin 'createdb.exe') -h 127.0.0.1 -p 55496 -U quality_fixture factory_lean_quality_local
if($LASTEXITCODE){throw 'createdb failed'}
function RunSql([string]$file,[string]$log){$prior=$ErrorActionPreference;try{$ErrorActionPreference='Continue';& (Join-Path $bin 'psql.exe') -X -h 127.0.0.1 -p 55496 -U quality_fixture -d factory_lean_quality_local -v ON_ERROR_STOP=1 -f $file *> (Join-Path $root $log);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$prior};if($code){throw "SQL failed: $log; owned local fixture retained at $root"}}
RunSql (Join-Path $repo 'tests/quality/local-bootstrap.sql') 'bootstrap.txt'
$migrations=@(Get-ChildItem (Join-Path $repo 'supabase/migrations') -Filter '*.sql'|Where-Object Name -ne '20261006072000_factory_export_reader.sql'|Sort-Object Name)
if($migrations.Count -ne 111){throw 'Unexpected migration count'}
$includes=$migrations|ForEach-Object{if($_.Name -eq '20261026091412_manufactured_output_drillthrough_read_v4d.sql'){"\i '"+(Join-Path $repo 'tests/manufactured-output-phase4d/before.sql').Replace('\','/')+"'"};if($_.Name -eq '20261010061827_quality_source_stock_v1.sql'){"\i '"+(Join-Path $repo 'tests/quality/pre-source-fixture.sql').Replace('\','/')+"'"};"\i '"+$_.FullName.Replace('\','/')+"'"}
$includes|Set-Content (Join-Path $root 'chain.sql');RunSql (Join-Path $root 'chain.sql') 'migrations.txt'
RunSql (Join-Path $repo 'tests/maintenance-planning/fixture.sql') 'existing-fixture.txt'
RunSql (Join-Path $repo 'tests/production-late-recording/fixture.sql') 'late-fixture.txt'
RunSql (Join-Path $repo 'tests/manufactured-output-phase2/fixture.sql') 'output-helper.txt'
$fixture=(Get-Content (Join-Path $repo 'tests/manufactured-output-phase4/fixture.sql') -Raw).Replace('not in (55490,55491)','<>55496')
$fixture|Set-Content (Join-Path $root 'completion-fixture.sql');RunSql (Join-Path $root 'completion-fixture.sql') 'completion-fixture.txt'
RunSql (Join-Path $PSScriptRoot 'fixture.sql') 'fixture.txt'
$context=& (Join-Path $bin 'psql.exe') -X -qAt -h 127.0.0.1 -p 55496 -U quality_fixture -d factory_lean_quality_local -c 'select x from planning_v3_test.context'
if($LASTEXITCODE){throw 'Context unavailable'}
[ordered]@{marker='FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY';root=$root;repo=$repo;app=$app;bin=$bin;database='factory_lean_quality_local';databaseHost='127.0.0.1';databasePort=55496;backendPort=4304;applicationPort=4222;context=($context|ConvertFrom-Json);gates='Shipped FALSE; isolated helper predicate only'}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $root 'runtime.json')
# Shared disposable adapter mirrors existing public grants; no per-preview RPC patch.
$backend=Start-Process node -ArgumentList @((Join-Path $repo 'tests/production-recording-full-app/backend.mjs'),(Join-Path $root 'runtime.json')) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'backend.txt') -RedirectStandardError (Join-Path $root 'backend-error.txt')
$web=Start-Process node -WorkingDirectory $app -ArgumentList @((Join-Path $repo 'node_modules/next/dist/bin/next'),'start','-H','127.0.0.1','-p','4222') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'web.txt') -RedirectStandardError (Join-Path $root 'web-error.txt')
@{backend=$backend.Id;web=$web.Id}|ConvertTo-Json|Set-Content (Join-Path $root 'processes.json')
Write-Output "Local preview http://127.0.0.1:4222/ — $root"
