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
, version ? "0.3.1"
}:
let
  url = "https://github.com/input-output-hk/jormungandr/releases/download/v${version}/jormungandr-v${version}-x86_64-pc-windows-gnu.zip";
  src = if (chocoReleaseOverride != null) then
      chocoReleaseOverride
    else (fetchurl {
      inherit url;
      sha256 = {
       "0.3.1" = "1b2k7g509diaqvir8rigb92amjiw80y60p2k439rmd2la5n29cji";
       "0.3.0" = "0c3342cfzj1jk31k5ni3i6ln4h47qkqyqvnwwd07a768rq3kbay6";
       "0.2.4" = "1vj6krg0j6mhmcvpb0wwppzxdbz4v3q45y2nzzva1s22yg8yihxq";
      }.${version};
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
