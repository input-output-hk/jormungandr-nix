$ErrorActionPreference = 'Stop'; # stop on all errors
$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
Get-ChocolateyUnzip "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\\release.zip" $toolsDir
$bootstrapFile = "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\\bootstrap-jormungandr.ps1"
Install-ChocolateyPowershellCommand -PSFileFullPath $bootstrapFile
Write-Host "`n`n**********`n`n"
Write-Host "To bootstrap a Jormungandr node use the command: bootstrap-jormungandr.bat"
Write-Host "The following executables are now in the path:`n  jcli.exe`n  jormungandr.exe`n  bootstrap-jormungandr.bat"
Write-Host "`n`n**********`n`n"
