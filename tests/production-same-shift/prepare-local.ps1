param([string]$RuntimeDirectory='C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-Runtime-20261018',[int]$Port=55497)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('FactoryLean-SameShift-SQL-'+[guid]::NewGuid().ToString('N'))
$bin=Join-Path $RuntimeDirectory 'pgsql/bin';$data=Join-Path $root 'data'
New-Item -ItemType Directory $root|Out-Null
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $root /inheritance:r /grant:r "*${sid}:(OI)(CI)F"|Out-Null
if($LASTEXITCODE){throw 'Owner ACL failed'}
Set-Content (Join-Path $env:TEMP 'FactoryLean-SameShift-SQL-location.txt') $root
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$Port);try{$listener.Start()}finally{$listener.Stop()}
& (Join-Path $bin 'initdb.exe') -D $data -U quality_fixture --encoding=UTF8 --locale=C --auth=trust *> (Join-Path $root 'initdb.txt');if($LASTEXITCODE){throw 'initdb failed'}
Add-Content (Join-Path $data 'postgresql.conf') "`nlisten_addresses='127.0.0.1'`nport=$Port`ntimezone='UTC'`n"
$p=Start-Process (Join-Path $bin 'pg_ctl.exe') -ArgumentList @('-D',('"'+$data+'"'),'-l',('"'+(Join-Path $root 'postgres.log')+'"'),'-w','start') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'start.txt') -RedirectStandardError (Join-Path $root 'start-error.txt')
if(!$p.WaitForExit(30000) -or $p.ExitCode){throw 'Owned PostgreSQL start failed'}
& (Join-Path $bin 'createdb.exe') -h 127.0.0.1 -p $Port -U quality_fixture factory_lean_quality_local;if($LASTEXITCODE){throw 'createdb failed'}
function RunSql([string]$file,[string]$log){$prior=$ErrorActionPreference;try{$ErrorActionPreference='Continue';& (Join-Path $bin 'psql.exe') -X -h 127.0.0.1 -p $Port -U quality_fixture -d factory_lean_quality_local -v ON_ERROR_STOP=1 -f $file *> (Join-Path $root $log);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$prior};if($code){throw "SQL failed: $log; owned fixture retained at $root"}}
RunSql (Join-Path $repo 'tests/quality/local-bootstrap.sql') 'bootstrap.txt'
$new='20261027111000_production_same_shift_completion_v3.sql'
$baseline=@(Get-ChildItem (Join-Path $repo 'supabase/migrations') -File -Filter '*.sql'|Where-Object Name -notin @('20261006072000_factory_export_reader.sql',$new)|Sort-Object Name)
if($baseline.Count -ne 111){throw 'Unexpected baseline migration count'}
$includes=$baseline|ForEach-Object{if($_.Name -eq '20261026091412_manufactured_output_drillthrough_read_v4d.sql'){"\i '"+(Join-Path $repo 'tests/manufactured-output-phase4d/before.sql').Replace('\','/')+"'"};if($_.Name -eq '20261010061827_quality_source_stock_v1.sql'){"\i '"+(Join-Path $repo 'tests/quality/pre-source-fixture.sql').Replace('\','/')+"'"};"\i '"+$_.FullName.Replace('\','/')+"'"}
$includes|Set-Content (Join-Path $root 'baseline.sql');RunSql (Join-Path $root 'baseline.sql') 'baseline.txt'
@'
do $$begin if private.manufactured_output_enabled(gen_random_uuid()) or exists(select 1 from private.production_recording_v3_activation where enabled or schema_contract_version<>0) then raise exception 'Shipped gates changed';end if;end$$;
'@|Set-Content (Join-Path $root 'inactive.sql');RunSql (Join-Path $root 'inactive.sql') 'inactive.txt'
RunSql (Join-Path $repo 'tests/maintenance-planning/fixture.sql') 'base-fixture.txt'
RunSql (Join-Path $repo 'tests/production-late-recording/fixture.sql') 'late-fixture.txt'
RunSql (Join-Path $repo 'tests/manufactured-output-phase2/fixture.sql') 'output-fixture.txt'
RunSql (Join-Path $PSScriptRoot 'before.sql') 'before.txt'
RunSql (Join-Path $repo ('supabase/migrations/'+$new)) 'migration.txt'
[ordered]@{marker='FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY';root=$root;bin=$bin;database='factory_lean_quality_local';databaseHost='127.0.0.1';databasePort=$Port}|ConvertTo-Json|Set-Content (Join-Path $root 'runtime.json')
Write-Output "Same-shift disposable SQL fixture ready: $root"
