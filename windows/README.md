# Building Chocolatey Packages

Both unsigned and signed chocolatey package builds are addressed below.

## Common Build Steps

- Ensure that in file `windows/default.nix`:

	-  The default version argument in the attribute header reflects the most current jormungandr release version [available](https://github.com/input-output-hk/jormungandr/releases) .

	- The corresponding `sha256` for the latest Jormungandr version exists and is correct.

- If necessary, update the `windows/tools/jormungandr-nuspec.nix` file with:
	- Any relevant changes to project parameters, such as package owner(s), project urls, description, etc.

- If necessary, update the `windows/tools/bootstrap-jormungandr.ps1` bootstrap script after checking:

	- If there are any breaking changes in the latest jormungandr [release](https://github.com/input-output-hk/jormungandr/releases) which will require PowerShell script modification to remain functional.

	- If there are any [upstream](https://raw.githubusercontent.com/input-output-hk/jormungandr/master/scripts/bootstrap.ps1) bootstrap script changes or improvements which should be included.

- In general, updating the `windows/tools/chocolateyinstall.ps1` and `windows/tools/chocolateybeforemodify.ps1` files will not be necessary.

## Building Unsigned Chocolatey Packages

- After ensuring the common build steps above are complete, building an unsigned chocolatey package is as simple as:

```sh
nix-build installers.nix -A chocoPackage
```
This will output a nix-store directory which contains the unsigned jormungandr chocolatey package in the form `jormungandr.${version}.nupkg`.

## Building Signed Chocolatey Packages

- ssh to the signing server
- Pull the latest jormungandr release windows gnu binary into the unsigned dir and unzip:

```sh
cd unsigned
# Fill in the actual version here:
version="${version}"

# Download the latest release and verify the sha hash is correct per the `windows/default.nix` file
nix-prefetch-url https://github.com/input-output-hk/jormungandr/releases/download/v${version}/jormungandr-v${version}-x86_64-pc-windows-gnu.zip

# Unzip
nix run nixpkgs.unzip -c unzip $NIX_STORE_PATH_TO_ZIP
```

- Move to the signing directory and sign the two jormungandr windows binaries, then zip the files up:

```sh
cd ../signed
../safeclient-nix/result/bin/sign -s ../unsigned/jcli.exe -d jcli.exe -n "Jormungandr" -u "https://github.com/input-output-hk/jormungandr" -i dcfd5ae14fcf6c13f7f7fc59d005dd7cfedfa212
../safeclient-nix/result/bin/sign -s ../unsigned/jormungandr.exe -d jormungandr.exe -n "Jormungandr" -u "https://github.com/input-output-hk/jormungandr" -i dcfd5ae14fcf6c13f7f7fc59d005dd7cfedfa212
nix run nixpkgs.zip -c zip release-${version}-signed.zip jcli.exe jormungandr.exe
```

- scp, or otherwise copy the signed binary zip to your server of choice for completing the chocolatey signed build.

- Suggested cleanup on the signing server: delete binaries and zip files created in the signed and unsigned directories.

- On your server of choice for completing the chocolatey signed build, move the signed binary zip to the root of the jormungandr-nix git directory.

- Using the signed binary zip, build the chocolatey package using an argument override to specify the signed binary zip rather than nix fetchurl the latest jormungandr version:

```sh
# Fill in the actual version here:
version="${version}"
nix-build installers.nix -A chocoPackage --arg chocoSignedZip "/release-${version}-signed.zip"
```

This will output a nix-store directory which contains the signed jormungandr chocolatey package in the form `jormungandr.${version}.nupkg`.

Instructions to verify that binaries are signed properly on a Windows platform are included in the `windows/tools/VERIFICATION.txt` file.

## Local Automated Chocolatey Testing

- Automated testing is done by the chocolatey upstream repo once a package is pushed to it.

- However, local tests can be done prior to pushing using a Windows 2012 virtual machine.

- References for local automated tests, including software and hardware requirements are found here:
	- [https://github.com/chocolatey/package-verifier/wiki](https://github.com/chocolatey/package-verifier/wiki)
	- [https://github.com/chocolatey-community/chocolatey-test-environment](https://github.com/chocolatey-community/chocolatey-test-environment)

- Example commands required to set up local automated testing on a NixOS system.  All commands below are entered into the NixOS system, not in to the Windows virtual machine:

```sh
# Install the dependencies; Virtualbox is assumed to be already installed as a NixOS option
cd <to-path-of-your-choice>
git clone https://github.com/chocolatey-community/chocolatey-test-environment.git
cd chocolatey-test-environment/
nix-shell -p powershell vagrant
vagrant plugin install sahara

# Enter a PowerShell to run the PowerShell Vagrantfile script
pwsh

# The first time `vagrant up` is run, it will take some time to download a W2012R2 datacenter server image
vagrant up

# Prepare the testing environment
vagrant sandbox on

# For testing local packages from the packages/ directory,
# uncomment the line in the Vagrant file just below `# THIS IS WHAT YOU CHANGE`
# that includes `--source "'c:\packages;http://chocolatey.org/api/v2'"`.
# On that uncommented line, replace `INSERT_NAME` with the name of your local package, without the version number or .nupkg file extension.
# Other modes of testing are described in the ReadMe.md file.
vim Vagrantfile

# The uncommented and edited line in the Vagrantfile should now look like the following (without the `` ticks):
`choco.exe install -fdvy jormungandr --allow-downgrade --source "'c:\\packages;http://chocolatey.org/api/v2/'"`

# Move the Chocolatey package to test to the `packages` folder after removing any other old test packages first
# The correct environment variable, ${version} is assumed to be already substituted into the filename.
rm packages/*.nupkg
cp <path-to>/jormungandr.${version}.nupkg packages/

# Test the package
vagrant provision

# Examine the testing output in the terminal the `vagrant provision` command was run
# Examine the Windows 2012R2 Virtualbox image for further debugging if needed
```

To re-test the same or another package when the testing image is already running and while still in a PowerShell:

```sh
vagrant sandbox rollback

# Repeat the steps above starting at editing the line which contained `INSERT_NAME`
```

To stop the vagrant testing environment virtual machine:

```sh
# Suspend the testing VM:
vagrant suspend

# or, halt the testing VM:
vagrant halt
```

To start the testing environment again after it has been suspended or halted:

```sh
# Install the dependencies; Virtualbox is assumed to be already installed as a NixOS option
cd <to-path-chocolatey-test-environment>
nix-shell -p powershell vagrant

# Enter a PowerShell to run the PowerShell Vagrantfile script
pwsh

# Start the vagrant image
vagrant up

# Repeat the steps above starting at editing the line which contained `INSERT_NAME`
```

## Local Manual Chocolatey Testing

Local chocolatey package testing can also be performed manually in a Windows environment using a VM or physical machine, including the VM testing environment described above.  To test manually in a local environment, the `jormungandr.${version}.nupkg` file should be moved to the Windows testing environment and the following capabilities tested:

```sh
# Choco is assumed to be already installed in the Windows Testing Environment (WTE) from an Administrator PowerShell.
# The `jormungandr.${version}.nupkg` package is assumed to already be in an otherwise empty current directory and where the ${version} variable has already be substituted into the filename.
# These commands are executed from an Administrative PowerShell in the WTE.

# All chocolatey script prompts are accepted as `[Y]es` or `[A]ll` here and below.
# To test an install when jormungandr is not already installed:
choco.exe install jormungandr -s .

# To test an upgrade; the force option is required since the upgrade is still the same version:
choco.exe upgrade jormungandr -f -s .

# Uninstall
choco.exe uninstall jormungandr

# To test the jormungandr bootstrap script and uninstall during jormungandr active execution;
# Re-install jormungandr:
choco.exe install jormungandr -s .

# Start the bootstrap jormungandr script, answering 'y' for 'yes' to any prompts:
bootstrap-jormungandr.bat

# In another administrative PowerShell window, uninstall jormungandr while bootstrap-jormungandr script is running:
choco.exe uninstall jormungandr
```

## Pushing a Chocolatey Package Upstream

To push a successfully tested chocolatey package upstream to the chocolatey repo:

```sh
# From the jormungandr-nix git root folder, enter the nuget shell:
nix-shell nuget-shell.nix

# Push the package to chocolatey where the environment variables $CHOCOKEY and $NUPKGFILE are substituted appropriately:
nuget push -ApiKey $CHOCOKEY -Source https://push.chocolatey.org $NUPKGFILE -Verbosity detailed
```
- A chocolatey API key may be obtained by creating an account at the chocolatey repo webite.

## Chocolatey Package Troubleshooting Tips

The following are known caveats and tips that may aid in troubleshooting:

- While testing on windows, the following additional chocolatey packages may help:

```sh
# chocolately checksum package allows calculation of sha256 file hashes on Windows
choco.exe install checksum

# chocolatey sysinternals package installs Windows diagnostic and debug tools
choco.exe install sysinternals

# chocolatey nugetpackageexplorer package allows chocolatey package inspection and modification
choco.exe install NugetPackageExplorer
```

- While uninstalling or upgrading jormungandr, errors will be observed in the chocolatey output if any command prompts, PowerShells, or Explorer windows are open to various chocolatey installation directories.  This is due to file/folder locking.  The chocolately uninstall or upgrade will still be successful despite error output being observed.

- A new version of a chocolatey package cannot be pushed upstream to chocolatey if another version of the same package is still under automated or manual review.

- The `bootstrap-jormungandr.bat` script may sometimes fail to start if it has been previously run and then stopped, even when specifying `yes` to purging former configuration, database and secrets.  The error output may look like the following:

```sh
Found an existing CONFIG folder (C:\Users\$USERNAME\AppData\Local\jormungandr\config) Remove it? (Default is Yes)
 ( Y / n ) : y
Yes, Remove former configuration
Found an existing DATA folder (C:\Users\$USERNAME\AppData\Local\jormungandr\storage) Remove it? (Default is Yes)
 ( Y / n ) : y
Yes, remove former database
Found an existing SECRET folder (C:\Users\$USERNAME\AppData\Local\jormungandr\secret) Remove it? (Default is Yes)
 ( y / n ) : y
Yes, Remove former secrets
Do you want to start it now?  ( y / N ) : y
$DATE INFO Starting jormungandr $VERSION, task: init
$DATE INFO storing blockchain in '"C:/Users/$USERNAME/AppData/Local/jormungandr/storage/blocks.sqlite"', task: init
$DATE INFO restoring state at tip $BLOCKHASH, task: bootstrap
Error while loading the legacy blockchain state
Error in the blockchain storage: block not found
```

- To remedy this, the storage folder can be manually purged using the path specified in the error output shown.  Example:

```sh
rm c:\Users\$USERNAME\AppData\Local\jormungandr\storage\
```
