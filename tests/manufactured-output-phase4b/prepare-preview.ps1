param([Parameter(Mandatory=$true)][string]$RuntimeDirectory,[Parameter(Mandatory=$true)][string]$ApplicationDirectory)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('FactoryLean-Output-P4B-Preview-'+[guid]::NewGuid().ToString('N'))
$app=(Resolve-Path $ApplicationDirectory).Path
if(-not $app.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path (Join-Path $app '.next/BUILD_ID'))){throw 'Explicit isolated built application required'}
$envText=Get-Content (Join-Path $app '.env.local') -Raw
if($envText -match 'https://' -or -not $envText.Contains('SUPABASE_URL=http://127.0.0.1:4300')){throw 'Not a loopback application'}
foreach($port in @(55492,4300,4218)){$test=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$port);try{$test.Start()}finally{$test.Stop()}}
New-Item -ItemType Directory $root | Out-Null
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $root /inheritance:r /grant:r "*${sid}:(OI)(CI)F" | Out-Null
if($LASTEXITCODE){throw 'Owner ACL failed'}
$bin=Join-Path $RuntimeDirectory 'pgsql/bin';$data=Join-Path $root 'data'
& (Join-Path $bin 'initdb.exe') -D $data -U quality_fixture --encoding=UTF8 --locale=C --auth=trust *> (Join-Path $root 'initdb.txt')
if($LASTEXITCODE){throw 'initdb failed'}
Add-Content (Join-Path $data 'postgresql.conf') "`nlisten_addresses='127.0.0.1'`nport=55492`ntimezone='UTC'`n"
$process=Start-Process (Join-Path $bin 'pg_ctl.exe') -ArgumentList @('-D',('"'+$data+'"'),'-l',('"'+(Join-Path $root 'postgres.log')+'"'),'-w','start') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'start.txt') -RedirectStandardError (Join-Path $root 'start-error.txt')
if(!$process.WaitForExit(30000) -or $process.ExitCode){throw 'PostgreSQL start failed'}
& (Join-Path $bin 'createdb.exe') -h 127.0.0.1 -p 55492 -U quality_fixture factory_lean_quality_local
if($LASTEXITCODE){throw 'createdb failed'}
function RunSql([string]$file,[string]$log){$prior=$ErrorActionPreference;try{$ErrorActionPreference='Continue';& (Join-Path $bin 'psql.exe') -X -h 127.0.0.1 -p 55492 -U quality_fixture -d factory_lean_quality_local -v ON_ERROR_STOP=1 -f $file *> (Join-Path $root $log);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$prior};if($code){throw "SQL setup failed: $log; local fixture retained: $root"}}
RunSql (Join-Path $repo 'tests/quality/local-bootstrap.sql') 'bootstrap.txt'
$migrations=@(Get-ChildItem (Join-Path $repo 'supabase/migrations') -Filter '*.sql' | Where-Object Name -ne '20261006072000_factory_export_reader.sql' | Sort-Object Name)
if($migrations.Count -ne 106){throw 'Unexpected local chain'}
$includes=$migrations | ForEach-Object{if($_.Name -eq '20261010061827_quality_source_stock_v1.sql'){"\i '"+(Join-Path $repo 'tests/quality/pre-source-fixture.sql').Replace('\','/')+"'"};"\i '"+$_.FullName.Replace('\','/')+"'"}
$includes | Set-Content (Join-Path $root 'chain.sql');RunSql (Join-Path $root 'chain.sql') 'migrations.txt'
@'
do $$begin if private.manufactured_output_enabled(gen_random_uuid()) or exists(select 1 from private.production_recording_v3_activation where enabled) then raise exception 'Shipped gate changed';end if;end$$;
'@ | Set-Content (Join-Path $root 'inactive.sql');RunSql (Join-Path $root 'inactive.sql') 'inactive.txt'
RunSql (Join-Path $repo 'tests/maintenance-planning/fixture.sql') 'existing-fixture.txt'
RunSql (Join-Path $repo 'tests/production-late-recording/fixture.sql') 'late-fixture.txt'
RunSql (Join-Path $repo 'tests/manufactured-output-phase2/fixture.sql') 'seed.txt'
# Only the test fixture's explicit loopback port assertion changes in this copy.
$fixture=(Get-Content (Join-Path $repo 'tests/manufactured-output-phase4/fixture.sql') -Raw).Replace('not in (55490,55491)','<>55492')
$fixture | Set-Content (Join-Path $root 'completion-fixture.sql');RunSql (Join-Path $root 'completion-fixture.sql') 'completion-fixture.txt'
$context=& (Join-Path $bin 'psql.exe') -X -qAt -h 127.0.0.1 -p 55492 -U quality_fixture -d factory_lean_quality_local -c "select output4_test.context('Phase4B local manual')"
if($LASTEXITCODE){throw 'Local context unavailable'}
[ordered]@{marker='FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY';root=$root;repo=$repo;app=$app;bin=$bin;database='factory_lean_quality_local';databaseHost='127.0.0.1';databasePort=55492;backendPort=4300;applicationPort=4218;context=($context | ConvertFrom-Json);gates='Shipped FALSE; disposable fixture predicate only';auth='test-only adapter; normal login; not hosted Supabase'} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $root 'runtime.json')
Set-Content (Join-Path ([IO.Path]::GetTempPath()) 'FactoryLean-Output-P4B-Preview-location.txt') $root
Write-Output "Prepared disposable Phase4B browser fixture: $root"
