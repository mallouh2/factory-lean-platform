param([Parameter(Mandatory=$true)][string]$RuntimeDirectory,[int]$Port=55470,[switch]$ExtractOnly,[switch]$Upgrade)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('FactoryLean-Correction-Policy-'+[guid]::NewGuid().ToString('N'))
$bin=Join-Path $RuntimeDirectory 'pgsql/bin'
$data=Join-Path $root 'data'
$results=Join-Path $root 'results'
New-Item -ItemType Directory -Path $results -Force | Out-Null
Write-Output "Evidence: $root"
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$Port)
try{$listener.Start()}finally{$listener.Stop()}
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
  $prior=$ErrorActionPreference
  try{$ErrorActionPreference='Continue'
   & (Join-Path $bin 'psql.exe') -X -h 127.0.0.1 -p $Port -U quality_fixture -d factory_lean_quality_local -v ON_ERROR_STOP=1 -f $file *> (Join-Path $results $name)
   $code=$LASTEXITCODE
  }finally{$ErrorActionPreference=$prior}
  if($code){throw "SQL failed: $name"}
 }
 RunSql (Join-Path $repo 'tests/quality/local-bootstrap.sql') 'bootstrap.txt'
 $migration=Join-Path $repo 'supabase/migrations/20261019114709_production_correction_approval_v1.sql'
 $baseline=@(Get-ChildItem (Join-Path $repo 'supabase/migrations') -File | Where-Object {$_.Name -ne '20261006072000_factory_export_reader.sql' -and $_.FullName -ne $migration} | Sort-Object Name)
 if($baseline.Count -ne 93){throw 'Unexpected pre-policy baseline'}
 $includes=$baseline | ForEach-Object {
  if($_.Name -eq '20261010061827_quality_source_stock_v1.sql'){"\i '"+(Join-Path $repo 'tests/quality/pre-source-fixture.sql').Replace('\','/')+"'"}
  "\i '"+$_.FullName.Replace('\','/')+"'"
 }
 $includes | Set-Content (Join-Path $root 'baseline.sql')
 RunSql (Join-Path $root 'baseline.sql') 'baseline.txt'
 if($ExtractOnly){
  foreach($spec in @(@('quantity','private.correct_production(uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,boolean,numeric,text)'),@('lean','private.correct_lean_production(uuid,jsonb,uuid)'))){
   & (Join-Path $bin 'psql.exe') -X -qAt -h 127.0.0.1 -p $Port -U quality_fixture -d factory_lean_quality_local -v ON_ERROR_STOP=1 -c ("select pg_get_functiondef('"+$spec[1]+"'::regprocedure)") | Set-Content -Encoding utf8 (Join-Path $results ($spec[0]+'.sql'))
   if($LASTEXITCODE){throw 'Definition extraction failed'}
  }
  Write-Output 'PASS: read-only definition extraction from disposable baseline.'
  return
 }
 $inputHashes=[ordered]@{}
 foreach($file in @($baseline)+(Get-Item $migration)+@(Get-ChildItem -LiteralPath $PSScriptRoot -File)){$inputHashes[$file.FullName]=(Get-FileHash -LiteralPath $file.FullName).Hash}
 $inputHashes | ConvertTo-Json | Set-Content (Join-Path $results 'input-hashes.json')
 function Fixtures {
  RunSql (Join-Path $repo 'tests/maintenance-planning/fixture.sql') 'mp-fixture.txt'
  RunSql (Join-Path $repo 'tests/production-late-recording/fixture.sql') 'late-fixture.txt'
  RunSql (Join-Path $repo 'tests/production-late-recording/writer.test.sql') 'writer.txt'
  RunSql (Join-Path $repo 'tests/production-reporting/seed.sql') 'reporting-seed.txt'
 }
 if($Upgrade){Fixtures}
 RunSql (Join-Path $PSScriptRoot 'before.sql') 'before.txt'
 RunSql $migration 'policy.txt'
 RunSql (Join-Path $PSScriptRoot 'after.sql') 'after.txt'
 if(-not $Upgrade){Fixtures}
 RunSql (Join-Path $PSScriptRoot 'fixture.sql') 'fixture.txt'
 RunSql (Join-Path $PSScriptRoot 'historical.test.sql') 'historical.txt'
 RunSql (Join-Path $PSScriptRoot 'policy.test.sql') 'policy-tests.txt'
 RunSql (Join-Path $PSScriptRoot 'security.test.sql') 'security.txt'
 & node (Join-Path $PSScriptRoot 'concurrency.mjs') $bin $Port $results *> (Join-Path $results 'concurrency.txt')
 if($LASTEXITCODE){throw 'Correction concurrency failed'}
 & node (Join-Path $PSScriptRoot 'http.mjs') $bin $Port $results *> (Join-Path $results 'http.txt')
 if($LASTEXITCODE){throw 'Correction HTTP integration failed'}
 foreach($file in @('reporting.test.sql','security.test.sql','temporal.test.sql','multiple.test.sql')){RunSql (Join-Path $repo ('tests/production-reporting/'+$file)) ('reporting-'+$file+'.txt')}
 foreach($file in @('boundary.test.sql','maintenance.test.sql','startup.test.sql')){RunSql (Join-Path $repo ('tests/production-late-recording/'+$file)) ('late-'+$file+'.txt')}
 & node (Join-Path $repo 'tests/production-late-recording/concurrency.mjs') $bin $Port $results *> (Join-Path $results 'late-concurrency.txt')
 if($LASTEXITCODE){throw 'M2 concurrency failed'}
 RunSql (Join-Path $repo 'tests/maintenance-planning/readiness-fixture.sql') 'readiness-fixture.txt'
 foreach($file in @('recording.test.sql','readiness.test.sql','transfers.test.sql')){RunSql (Join-Path $repo ('tests/maintenance-planning/'+$file)) ('maintenance-'+$file+'.txt')}
 foreach($file in @('source-stock.test.sql','release-fixes.test.sql')){RunSql (Join-Path $repo ('tests/quality/'+$file)) ('quality-'+$file+'.txt')}
 RunSql (Join-Path $PSScriptRoot 'final.sql') 'final.txt'
 foreach($file in $inputHashes.Keys){if((Get-FileHash -LiteralPath $file).Hash -ne $inputHashes[$file]){throw "Test input changed: $file"}}
 "PASS: local correction policy; Upgrade=$Upgrade; Export Reader excluded; not hosted Supabase." | Set-Content (Join-Path $results 'summary.txt')
 Get-Content (Join-Path $results 'summary.txt')
}finally{
 if($started){
  & (Join-Path $bin 'pg_ctl.exe') -D $data -m fast -w stop *> (Join-Path $results 'stop.txt')
  if($LASTEXITCODE){throw 'Owned database stop failed; data retained'}
 }
 $resolved=[IO.Path]::GetFullPath($data)
 $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if($root.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $root -Leaf).StartsWith('FactoryLean-Correction-Policy-') -and $resolved.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
  Remove-Item -LiteralPath $resolved -Recurse -Force
 }else{throw 'Unexpected disposable data path; cleanup refused'}
}
