$ErrorActionPreference = 'Stop'; # stop on all errors
$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
Get-ChocolateyUnzip "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\\release.zip" $toolsDir
$jtoolsFile = "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\\jtools.ps1"
Install-ChocolateyPowershellCommand -PSFileFullPath $jtoolsFile
Write-Output "`n`n**********`n`n"
Write-Output "The following executables are now in the path:`n  jcli.exe`n  jormungandr.exe`n  jtools.bat"
Write-Output "`n`n**********`n`n"
