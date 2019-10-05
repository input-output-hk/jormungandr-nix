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
, version ? "0.5.6"
}:
let
  url = "https://github.com/input-output-hk/jormungandr/releases/download/v${version}/jormungandr-v${version}-x86_64-pc-windows-gnu.zip";
  src = if (chocoReleaseOverride != null) then
      chocoReleaseOverride
    else (fetchurl {
      inherit url;
      sha256 = {
       "0.5.6" = "1lq4jr5isrx3haz7g9kwns92kh5d26qcdr9q64qgw5vxs1v3fcng";
       "0.5.5" = "0q7p69r372d153218khl3978qdhpd5dghrvccq7nmg0cpkah7d6f";
       "0.5.2" = "0k94ixf5d0vrrn248ida6ph7gc4zzp1j2sm66cj1wzn289p3bkd3";
       "0.5.0" = "1dyd1z6rcwx9z07x6hklk2lk6ivlwkcc1v4707fqjkm6gqk6bjwa";
       "0.3.999" = "0cnplldr827rf020s7qi9w215cidcgvkc6hpfqdxfxankxvffc6k";
       "0.3.3" = "1109lmh4d5k7xaqpkh7v3dw0z9jhqzbwmkd80l0c0sxqj2l3n7qn";
       "0.3.2" = "0yw6g02y9vdw7k5jmcmjbgwk63dicqkjm6lrawb40c6gvps1hmsf";
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
