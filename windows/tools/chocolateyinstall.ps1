$ErrorActionPreference = 'Stop'; # stop on all errors
$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
Get-ChocolateyUnzip "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\\release.zip" $toolsDir
Write-Host "`n`n**********`n`n"
Write-Host "The following executables are now in the path:`n  jcli.exe`n  jormungandr.exe"
Write-Host "`n`n**********`n`n"
