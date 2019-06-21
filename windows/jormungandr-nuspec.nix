{
  writeText
, version
}:

writeText "jormungandr-nuspec" ''
<?xml version="1.0" encoding="utf-8"?>

<package xmlns="http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd">
  <metadata>
    <id>jormungandr</id>
    <version>${version}</version>
    <packageSourceUrl>https://github.com/jormungandr</packageSourceUrl>
    <owners>IOHK</owners>

    <title>jormungandr (Install)</title>
    <authors>disassembler</authors>
    <projectUrl>https://github.com/input-output-hk/jormungandr</projectUrl>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <tags>jormungandr</tags>
    <summary>Cardano Node running on rust</summary>
    <description># Cardano Node running on rust</description>
  </metadata>
  <files>
    <file src="tools/**" target="tools" />
  </files>
</package>
''
