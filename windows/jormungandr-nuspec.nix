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
    <projectUrl>https://testnet.iohkdev.io/cardano/shelley/about/testnet-introduction/</projectUrl>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <tags>jormungandr</tags>
    <summary>Jormungandr: Cardano Node running on Rust</summary>
    <description>This package will install IOHK's Jormungandr compiled binaries which provide Cardano Blockchain node capability running on Rust.

Jormungandr is a node implementation with the initial aim to support the Ouroboros type of consensus protocol.  A node is a participant of a blockchain network, continuously making, sending, receiving, and validating blocks. Each node is responsible to make sure that all the rules of the protocol are followed.

Once this chocolatey package is installed, jcli.exe and jormungandr.exe binaries will be available on the command line. See the documentation for usage.</description>
    <docsUrl>https://input-output-hk.github.io/jormungandr/</docsUrl>
    <bugTrackerUrl>https://github.com/input-output-hk/jormungandr/issues</bugTrackerUrl>
    <projectSourceUrl>https://github.com/input-output-hk/jormungandr</projectSourceUrl>
    <releaseNotes>https://github.com/input-output-hk/jormungandr/releases</releaseNotes>
    <licenseUrl>https://raw.githubusercontent.com/input-output-hk/jormungandr/master/LICENSE-APACHE</licenseUrl>
  </metadata>
  <files>
    <file src="tools/**" target="tools" />
  </files>
</package>
''
