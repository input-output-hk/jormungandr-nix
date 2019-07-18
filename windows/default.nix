{
  stdenv
, runCommand
, writeText
, writeScript
, curl
, unzip
, docker
, choco
, chocoReleaseOverride
, fetchurl
, version ? "0.3.0"
}:
let
  url = "https://github.com/input-output-hk/jormungandr/releases/download/v${version}/jormungandr-v${version}-x86_64-pc-windows-gnu.zip";
  src = if (chocoReleaseOverride != null) then
      chocoReleaseOverride
    else (fetchurl {
      inherit url;
      sha256 = "0c3342cfzj1jk31k5ni3i6ln4h47qkqyqvnwwd07a768rq3kbay6";
  });
  nuspec = import ./jormungandr-nuspec.nix { inherit writeText version; };

in runCommand "build-choco-jormungandr" { buildInputs = [ unzip choco.mono ]; } ''
  mkdir -p build $out
  pushd build
  ls -hal
  cp ${nuspec} ./jormungandr.nuspec
  cp -a ${./tools} tools
  chmod 0755 tools
  pushd tools
  cp ${src} release.zip
  ls -la
  popd
  mono ${choco}/bin/choco.exe pack ./jormungandr.nuspec --allow-unofficial
  cp jormungandr.${version}.nupkg $out/
  popd
''
