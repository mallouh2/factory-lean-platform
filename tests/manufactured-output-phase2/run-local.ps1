param([Parameter(Mandatory=$true)][string]$RuntimeDirectory,[int]$Port=55484)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('FactoryLean-Output-P2-SQL-'+[guid]::NewGuid().ToString('N'))
$bin=Join-Path $RuntimeDirectory 'pgsql/bin';$data=Join-Path $root 'data';$results=Join-Path $root 'results'
New-Item -ItemType Directory -Path $results | Out-Null
Write-Output "Evidence: $root"
Set-Content (Join-Path ([IO.Path]::GetTempPath()) 'FactoryLean-Output-P2-SQL-location.txt') $root
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
 $migration=Join-Path $repo 'supabase/migrations/20261024075746_manufactured_output_recording_quality_v2.sql'
 $baseline=@(Get-ChildItem (Join-Path $repo 'supabase/migrations') -Filter '*.sql' | Where-Object {$_.Name -ne '20261006072000_factory_export_reader.sql' -and $_.FullName -ne $migration} | Sort-Object Name)
 if($baseline.Count -ne 101){throw 'Unexpected baseline'}
 $hashes=[ordered]@{}
 foreach($file in @($baseline)+(Get-Item $migration)+@(Get-ChildItem $PSScriptRoot -File)){$hashes[$file.FullName]=(Get-FileHash $file.FullName).Hash}
 $hashes | ConvertTo-Json | Set-Content (Join-Path $results 'input-hashes.json')
 $includes=$baseline | ForEach-Object{if($_.Name -eq '20261010061827_quality_source_stock_v1.sql'){"\i '"+(Join-Path $repo 'tests/quality/pre-source-fixture.sql').Replace('\','/')+"'"};"\i '"+$_.FullName.Replace('\','/')+"'"}
 $includes | Set-Content (Join-Path $root 'baseline.sql');RunSql (Join-Path $root 'baseline.sql') 'baseline.txt'

 RunSql $migration 'migration.txt'

 RunSql (Join-Path $repo 'tests/maintenance-planning/fixture.sql') 'fixture-base.txt'
 RunSql (Join-Path $repo 'tests/production-late-recording/fixture.sql') 'late-fixture.txt'
 RunSql (Join-Path $PSScriptRoot 'fixture.sql') 'fixture.txt'
 RunSql (Join-Path $PSScriptRoot 'integration.test.sql') 'integration.txt'
 & node (Join-Path $PSScriptRoot 'concurrency.mjs') $bin $Port $results *> (Join-Path $results 'concurrency.txt')
 if($LASTEXITCODE){throw 'Concurrency failed'}
 foreach($file in $hashes.Keys){if((Get-FileHash -LiteralPath $file).Hash -ne $hashes[$file]){throw "Test input changed: $file"}}
 'PASS: inactive Phase2; focused integration SQL. No hosted access.' | Set-Content (Join-Path $results 'summary.txt')
 Get-Content (Join-Path $results 'summary.txt')
}finally{
 if($started){& (Join-Path $bin 'pg_ctl.exe') -D $data -m fast -w stop *> (Join-Path $results 'stop.txt');if($LASTEXITCODE){throw 'Owned DB stop failed'}}
 $absolute=[IO.Path]::GetFullPath($data);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if($root.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $root -Leaf).StartsWith('FactoryLean-Output-P2-SQL-') -and $absolute.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $absolute -Recurse -Force}else{throw 'Unsafe cleanup'}
}
