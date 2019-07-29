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
    <packageSourceUrl>https://github.com/input-output-hk/jormungandr-nix/tree/master/windows</packageSourceUrl>
    <owners>disasm,johnalotoski</owners>

    <title>jormungandr (Install)</title>
    <authors>Input Output HK Limited</authors>
    <projectUrl>https://testnet.iohkdev.io/cardano/shelley/get-started/setting-up-the-self-node/</projectUrl>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <tags>jormungandr</tags>
    <summary>Jormungandr: Cardano Node running on Rust</summary>
    <description>This package will install IOHK's Jormungandr compiled binaries which provide Cardano Blockchain node capability running on Rust</description>
    <docsUrl>https://input-output-hk.github.io/jormungandr/</docsUrl>
    <bugTrackerUrl>https://github.com/input-output-hk/jormungandr/issues</bugTrackerUrl>
    <projectSourceUrl>https://github.com/input-output-hk/jormungandr</projectSourceUrl>
    <releaseNotes>https://github.com/input-output-hk/jormungandr/releases</releaseNotes>
  </metadata>
  <files>
    <file src="tools/**" target="tools" />
  </files>
</package>
''
