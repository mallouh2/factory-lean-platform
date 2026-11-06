param([Parameter(Mandatory=$true)][string]$RuntimeDirectory,[int]$DatabasePort=55490,[int]$BackendPort=4299,[int]$ApplicationPort=4217)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('FactoryLean-Output-P4-Preview-'+[guid]::NewGuid().ToString('N'))
foreach($port in @($DatabasePort,$BackendPort,$ApplicationPort)){$test=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$port);try{$test.Start()}finally{$test.Stop()}}
New-Item -ItemType Directory $root|Out-Null
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $root /inheritance:r /grant:r "*${sid}:(OI)(CI)F"|Out-Null
if($LASTEXITCODE){throw 'Owner ACL failed'}
$bin=Join-Path $RuntimeDirectory 'pgsql/bin';$data=Join-Path $root 'data'
& (Join-Path $bin 'initdb.exe') -D $data -U quality_fixture --encoding=UTF8 --locale=C --auth=trust *> (Join-Path $root 'initdb.txt')
if($LASTEXITCODE){throw 'initdb failed'}
Add-Content (Join-Path $data 'postgresql.conf') "`nlisten_addresses='127.0.0.1'`nport=$DatabasePort`ntimezone='UTC'`n"
$process=Start-Process (Join-Path $bin 'pg_ctl.exe') -ArgumentList @('-D',('"'+$data+'"'),'-l',('"'+(Join-Path $root 'postgres.log')+'"'),'-w','start') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'start.txt') -RedirectStandardError (Join-Path $root 'start-error.txt')
if(!$process.WaitForExit(30000) -or $process.ExitCode){throw 'PostgreSQL start failed'}
& (Join-Path $bin 'createdb.exe') -h 127.0.0.1 -p $DatabasePort -U quality_fixture factory_lean_quality_local
if($LASTEXITCODE){throw 'createdb failed'}
function RunSql([string]$file,[string]$log){$prior=$ErrorActionPreference;try{$ErrorActionPreference='Continue';& (Join-Path $bin 'psql.exe') -X -h 127.0.0.1 -p $DatabasePort -U quality_fixture -d factory_lean_quality_local -v ON_ERROR_STOP=1 -f $file *> (Join-Path $root $log);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$prior};if($code){throw "SQL setup failed: $log; fixture preserved at $root"}}
RunSql (Join-Path $repo 'tests/quality/local-bootstrap.sql') 'bootstrap.txt'
$migrations=@(Get-ChildItem (Join-Path $repo 'supabase/migrations') -File|Where-Object Name -ne '20261006072000_factory_export_reader.sql'|Sort-Object Name)
if($migrations.Count -ne 104){throw 'Unexpected local chain'}
$includes=$migrations|ForEach-Object{if($_.Name -eq '20261010061827_quality_source_stock_v1.sql'){"\i '"+(Join-Path $repo 'tests/quality/pre-source-fixture.sql').Replace('\','/')+"'"};"\i '"+$_.FullName.Replace('\','/')+"'"}
$includes|Set-Content (Join-Path $root 'chain.sql');RunSql (Join-Path $root 'chain.sql') 'migrations.txt'
RunSql (Join-Path $repo 'tests/maintenance-planning/fixture.sql') 'existing-fixture.txt'
RunSql (Join-Path $repo 'tests/production-late-recording/fixture.sql') 'late-fixture.txt'
RunSql (Join-Path $repo 'tests/manufactured-output-phase2/fixture.sql') 'seed.txt'
RunSql (Join-Path $repo 'tests/manufactured-output-phase4/fixture.sql') 'completion-fixture.txt'
$context=& (Join-Path $bin 'psql.exe') -X -qAt -h 127.0.0.1 -p $DatabasePort -U quality_fixture -d factory_lean_quality_local -c "select output4_test.context('Phase4 manual preview')"
if($LASTEXITCODE){throw 'Fixture context unavailable'}
$app=Join-Path $root 'app';New-Item -ItemType Directory $app|Out-Null
foreach($folder in @('src','public','scripts')){Copy-Item -LiteralPath (Join-Path $repo $folder) -Destination $app -Recurse}
foreach($file in @('package.json','package-lock.json','tsconfig.json','next-env.d.ts','next.config.ts')){Copy-Item -LiteralPath (Join-Path $repo $file) -Destination $app}
New-Item -ItemType Junction -Path (Join-Path $app 'node_modules') -Target (Join-Path $repo 'node_modules')|Out-Null
# This environment file belongs only to the disposable application copy.
@("APP_ENV=development","APP_ORIGIN=http://127.0.0.1:$ApplicationPort","SUPABASE_URL=http://127.0.0.1:$BackendPort","SUPABASE_PUBLISHABLE_KEY=local-preview-public-not-a-hosted-key","NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:$BackendPort","NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=local-preview-public-not-a-hosted-key","NEXT_TELEMETRY_DISABLED=1")|Set-Content (Join-Path $app '.env.local')
[ordered]@{marker='FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY';root=$root;repo=$repo;app=$app;bin=$bin;database='factory_lean_quality_local';databaseHost='127.0.0.1';databasePort=$DatabasePort;backendPort=$BackendPort;applicationPort=$ApplicationPort;context=($context|ConvertFrom-Json);gates='FALSE';auth='test-only protocol adapter; normal application sign-in; not hosted GoTrue'}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $root 'runtime.json')
$migrations|ForEach-Object{@{name=$_.Name;hash=(Get-FileHash $_.FullName).Hash}}|ConvertTo-Json|Set-Content (Join-Path $root 'migration-manifest.json')
Set-Content (Join-Path ([IO.Path]::GetTempPath()) 'FactoryLean-Output-P4-Preview-location.txt') $root
Write-Output "Prepared real application copy and disposable backend: $root"
