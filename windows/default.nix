{
  stdenv
, runCommand
, writeText
, writeScript
, curl
, unzip
, docker
, version ? "0.2.1"
}:
let
  url = "https://github.com/input-output-hk/jormungandr/releases/download/v${version}/jormungandr-v${version}-x86_64-pc-windows-gnu.zip";
  tools = ./tools;
  deps = [ curl unzip docker ];
  nuspec = import ./jormungandr-nuspec.nix { inherit writeText version; };

# TODO: get choco working with mono so builds can be pure
in writeScript "build-choco-jormungandr" ''
  #!${stdenv.shell} -e
  export PATH=${stdenv.lib.makeBinPath deps}:$PATH
  chmod -R u+rw build
  rm -rf build
  mkdir -p build
  curl -L ${url} -o build/release.zip
  pushd build
  ls -hal
  cp ${nuspec} ./jormungandr.nuspec
  cp -a ${tools} tools
  chmod 0755 tools
  pushd tools
  unzip ../release.zip
  popd
  rm release.zip
  popd
  docker run --rm -v $PWD:$PWD -w $PWD/build linuturk/mono-choco pack
''
