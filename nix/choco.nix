{ stdenv
, lib
, fetchFromGitHub
, fetchurl
, mono
, pkgconfig
, strace
, curl
, pkgs
}:

let
  nugetCache = "nugetCache";
  nupkgSpecs = builtins.fromJSON (builtins.readFile ./nugetpkgs-mono.json);

  nupkgs = let
    fetch = n: v:
      fetchurl {
        inherit (v) sha256;
        url = "https://www.nuget.org/api/v2/package/${n}/${v.ver}";
      };
  in (pkgs.lib.mapAttrs' (n: v: pkgs.lib.nameValuePair (v.filename) (fetch n v)) nupkgSpecs);

  copyNupkgs = n: v: "cp ${v} /build/source/${nugetCache}/${n}";
  copyAllNupkgs = pkgs.lib.concatStringsSep "\n" (pkgs.lib.mapAttrsFlatten copyNupkgs nupkgs);

  installNupkgs = n: v: "mono \"../../lib/NuGet/NuGet.exe\" install \"${n}\" -Version \"${v.ver}\"";
  installAllNupkgs = pkgs.lib.concatStringsSep "\n" (pkgs.lib.mapAttrsFlatten installNupkgs nupkgSpecs);

in stdenv.mkDerivation rec {
  name = "Choco";
  version = "0.10.15";
  src = fetchFromGitHub {
    owner = "chocolatey";
    repo = "choco";
    rev = version;
    sha256 = "0lj1jwwmh3ivvyfia3s15qyp5pad3s16yc7msggpdhipdqji15z4";
  };

  NuGetCachePath = "/build/source/${nugetCache}";

  buildInputs = [ mono pkgconfig strace curl ];
  patches = [ ./restore-debug.patch ./uppercut.patch ];
  xbuild = "${mono}/bin/xbuild";

  postPatch = ''
    substituteAll .uppercut .uppercut
    ls -la /
  '';
  buildPhase = ''
    mkdir -p ${nugetCache}
    echo -e "\n\nHere is what's currently in the cache..."
    cd /build/source/${nugetCache}
    # ls -la /build/source/${nugetCache}
    ls -la
    echo -e "\n\nGoing to show copyAllNupkgs..."
    echo -e "${copyAllNupkgs}"
    echo -e "\n\n"
    ${copyAllNupkgs}
    echo -e "\n\nHere is now what's in the cache..."
    ls -la /build/source/${nugetCache}
    exit 1
    ls -la
    cd src/packages
    ls -la
    export NuGetCachePath="/build/source/${nugetCache}"
    echo
    echo
    echo Going to show installAllNupkgs...
    echo    ${installAllNupkgs}
    ${installAllNupkgs}
    exit 1

    #mono "../../lib/NuGet/NuGet.exe" install "coveralls.io" -Version "1.1.86"
    # NuGetCachePath="/build/source/${nugetCache}" strace -f -e trace=file,network mono "../../lib/NuGet/NuGet.exe" install "coveralls.io" -Version "1.1.86"
    # exit 1
    #cd /build/source
    #mono --runtime=v4.0.30319 ./lib/NAnt/NAnt.exe /logger:"NAnt.Core.DefaultLogger" /nologo /quiet /f:"/build/source/.build/default.build" /D:build.config.settings="/build/source/.uppercut" /D:microsoft.framework="mono-4.0" /D:run.ilmerge="false" /D:run.nuget="false" $*
    # mono --runtime=v4.0.30319 ./lib/NAnt/NAnt.exe /logger:"NAnt.Core.DefaultLogger" /nologo /quiet /f:"$(cd $(dirname "$0"); pwd)/.build/default.build" /D:build.config.settings="$(cd $(dirname "$0"); pwd)/.uppercut" /D:microsoft.framework="mono-4.0" /D:run.ilmerge="false" /D:run.nuget="false" $*

    # Testing
    mkdir build_outputs
    cd build_outputs
    #echo Find
    #find . -iname "*solutionversion*"
    #whoami
    #ls -la /var/run/nscd/socket
    # /build/source/lib/NuGet/NuGet.exe restore '/build/source/src/chocolatey.sln'
    #echo ../lib/NuGet/NuGet.exe restore ../src/chocolatey.sln
    # strace -f -e trace=network,open,stat mono "../lib/NuGet/NuGet.exe" restore "../src/chocolatey.sln" -Verbosity "detailed"
    # /nix/store/33ks06akl0f267xrr0dl1bn9lpdvigp1-mono-3.12.1/bin/xbuild /build/source/src/chocolatey.sln /nologo /property:OutputPath='/build/source/build_output/chocolatey' /property:Configuration=Release /verbosity:detailed /toolsversion:4.0 /property:Platform='Any CPU' /property:TargetFrameworkVersion=v4.0 /l:ThoughtWorks.CruiseControl.MSBuild.XmlLogger,"/build/source/lib/NAnt/ThoughtWorks.CruiseControl.MSBuild.dll";'/build/source/build_output/build_artifacts/compile/msbuild-mono-4.0-results.xml'
    #pwd
    #ls -la src/packages
    #echo Find
    #find . -iname "*solutionversion*"
    exit 1
  '';

  doCheck = false;

  meta = with lib; {
    description = "Chocolatey choco package manager";
    homepage = https://chocolatey.org;
    license = licenses.asl20;
  };
}
