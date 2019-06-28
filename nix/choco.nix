{ stdenv
, lib
, fetchFromGitHub
, mono
, pkgconfig
}:


stdenv.mkDerivation rec {
  name = "Choco";
  version = "0.10.15";
  src = fetchFromGitHub {
    owner = "chocolatey";
    repo = "choco";
    rev = version;
    sha256 = "0lj1jwwmh3ivvyfia3s15qyp5pad3s16yc7msggpdhipdqji15z4";
  };

  buildInputs = [ mono pkgconfig ];
  buildPhase = ''
    mono --runtime=v4.0.30319 ./lib/NAnt/NAnt.exe /logger:"NAnt.Core.DefaultLogger" /nologo /quiet /f:"$(cd $(dirname "$0"); pwd)/.build/default.build" /D:build.config.settings="$(cd $(dirname "$0"); pwd)/.uppercut" /D:microsoft.framework="mono-4.0" /D:run.ilmerge="false" /D:run.nuget="false" $*

#/quiet /nologo /debug /verbose /t:"mono-4.0"


  '';

  doCheck = false;

  meta = with lib; {
    description = "Chocolatey choco package manager";
    homepage = https://chocolatey.org;
    license = licenses.asl20;
  };
}
