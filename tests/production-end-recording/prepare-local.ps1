$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$sourceRoot=(Get-Content (Join-Path $env:TEMP 'FactoryLean-Compensation-Fix-location.txt')).Trim()
$source=Get-Content (Join-Path $sourceRoot 'gantt-runtime.json')|ConvertFrom-Json
if($source.marker -ne 'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY' -or $source.databaseHost -ne '127.0.0.1' -or $source.databasePort -ne 55499 -or $source.root -ne $sourceRoot){throw 'Source is not the disposable QA copy'}
$bin=$source.bin
$actual=& "$bin/psql.exe" -X -qAt -h 127.0.0.1 -p 55499 -U quality_fixture -d factory_lean_quality_local -v ON_ERROR_STOP=1 -c "select json_build_object('host',inet_server_addr(),'port',inet_server_port(),'database',current_database(),'data',current_setting('data_directory'))"
if($LASTEXITCODE){throw 'Source check failed'};$actual=$actual|ConvertFrom-Json
if($actual.host -ne '127.0.0.1' -or $actual.port -ne 55499 -or $actual.database -ne 'factory_lean_quality_local' -or [IO.Path]::GetFullPath($actual.data) -ne [IO.Path]::GetFullPath((Join-Path $sourceRoot 'data'))){throw 'Source database mismatch'}
foreach($port in @(55500,4322,4238)){if(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue){throw "Port occupied: $port"}}
$root=Join-Path $env:TEMP ('FactoryLean-Production-End-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $root|Out-Null
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $root /inheritance:r /grant:r "*${sid}:(OI)(CI)F"|Out-Null;if($LASTEXITCODE){throw 'Owner ACL failed'}
[IO.File]::WriteAllText((Join-Path $env:TEMP 'FactoryLean-Production-End-location.txt'),$root)
# The installed portable runtime is minimal (no pg_dump). A clean, cold copy
# with the same binaries retains the existing roles, RLS and synthetic users.
$connections=& "$bin/psql.exe" -X -qAt -h 127.0.0.1 -p 55499 -U quality_fixture -d factory_lean_quality_local -c "select count(*)from pg_stat_activity where backend_type='client backend'and pid<>pg_backend_pid()"
if($LASTEXITCODE -or $connections -ne '0'){throw 'QA has other connected clients; do not stop it'}
& "$bin/pg_ctl.exe" -D "$sourceRoot/data" -w stop *> "$root/source-stop.txt";if($LASTEXITCODE){throw 'Clean QA shutdown failed'}
Copy-Item -LiteralPath "$sourceRoot/data" -Destination "$root/data" -Recurse
if(Test-Path "$root/data/postmaster.pid"){throw 'Cold clone unexpectedly contains live PID'}
Add-Content "$root/data/postgresql.conf" "`nlisten_addresses='127.0.0.1'`nport=55500`ntimezone='UTC'`n"
& "$bin/pg_ctl.exe" -D "$root/data" -l "$root/postgres.log" -w start *> "$root/start.txt";if($LASTEXITCODE){throw 'Local database start failed'}
Copy-Item "$sourceRoot/local-credentials.json","$sourceRoot/LOCAL-LOGIN.txt" -Destination $root
$source.root=$root;$source.databasePort=55500;$source.backendPort=4322;$source.applicationPort=4238;$source.app=Join-Path $root 'app'
[IO.File]::WriteAllText("$root/runtime.json",($source|ConvertTo-Json -Depth 15))
Write-Output "Disposable fixture clone ready: $root (55500/4322/4238). Existing identities copied, no new accounts."
