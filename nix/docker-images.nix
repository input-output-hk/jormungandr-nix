{ dockerTools
, bash
, coreutils
, jormungandr-bootstrap
}:
with dockerTools; {
  jormungandr-standalone = buildImage {
    name = "jormungandr-standalone";
    tag = "0.3.0";

    fromImage = pullImage{
      imageName = "lnl7/nix";
      finalImageTag = "2.2.2";
      imageDigest = "sha256:068140dbeb7cf8349f789ef2f547bf06c33227dd5c2b3cd9db238d5f57a1fb6a";
      sha256 = "1yjqdcb1ipa978693282cnr24sbk0yihm23xmg68k7ymah7ka9g5";
    };

    runAsRoot = ''
      mkdir -p /data
    '';

    config = {
      Env = [ "GELF=false" ];
      Cmd = [ "${bash}/bin/bash" "${jormungandr-bootstrap}/bin/bootstrap" "-a" ];
      WorkingDir = "/data";
      Volumes = {
        "/data" = {};
      };
      ExposedPorts = {
        "8299/tcp" = {};
        "8443/tcp" = {};
      };
    };
  };
}
