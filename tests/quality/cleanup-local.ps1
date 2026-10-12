param([Parameter(Mandatory=$true)][string]$TestDirectory,[Parameter(Mandatory=$true)][string]$RuntimeDirectory)
$ErrorActionPreference='Stop'
$qualityRoot=[IO.Path]::GetFullPath($TestDirectory)
$qualityTemp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
if(-not $qualityRoot.StartsWith($qualityTemp,[StringComparison]::OrdinalIgnoreCase) -or -not (Split-Path $qualityRoot -Leaf).StartsWith('FactoryLean-Quality-Postgres-')){throw 'Dedicated Quality temporary directory required'}
$qualityData=[IO.Path]::GetFullPath((Join-Path $qualityRoot 'data'))
if(-not $qualityData.StartsWith($qualityRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe data path'}
if(Test-Path -LiteralPath $qualityData){
 if(-not(Test-Path -LiteralPath (Join-Path $qualityData 'PG_VERSION'))){throw 'Refusing to remove an unidentified directory'}
 $qualityCtl=Join-Path $RuntimeDirectory 'pgsql/bin/pg_ctl.exe'
 & $qualityCtl -D $qualityData status
 if($LASTEXITCODE -eq 0){& $qualityCtl -D $qualityData -m fast -w stop;if($LASTEXITCODE){throw 'Owned PostgreSQL did not stop'}}
 elseif($LASTEXITCODE -ne 3){throw 'Cannot verify PostgreSQL status'}
 Remove-Item -LiteralPath $qualityData -Recurse -Force
}
Write-Output 'Owned disposable PostgreSQL data removed; scripts and results retained.'
