$ErrorActionPreference = 'Stop'; # stop on all errors
$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
Get-ChocolateyUnzip "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\\release.zip" $toolsDir
