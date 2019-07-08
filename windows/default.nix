{
  stdenv
, runCommand
, writeText
, writeScript
, curl
, unzip
, docker
, choco
, fetchurl
, version ? "0.2.4"
}:
let
  url = "https://github.com/input-output-hk/jormungandr/releases/download/v${version}/jormungandr-v${version}-x86_64-pc-windows-gnu.zip";
  src = fetchurl {
    inherit url;
    sha256 = "003m74f3g0rz250zmak09klzpw0vnsb1lkndnxlqqs2a3iywmvkv";
  };
  nuspec = import ./jormungandr-nuspec.nix { inherit writeText version; };

# TODO: get choco working with mono so builds can be pure
in runCommand "build-choco-jormungandr" { buildInputs = [ unzip choco.mono ]; } ''
  mkdir -p build $out
  pushd build
  ls -hal
  cp ${nuspec} ./jormungandr.nuspec
  cp -a ${./tools} tools
  chmod 0755 tools
  pushd tools
  unzip ${src}
  popd
  mono ${choco}/bin/choco.exe pack ./jormungandr.nuspec --allow-unofficial
  cp jormungandr.${version}.nupkg $out/
  popd
''
