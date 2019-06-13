{ pkgs, ... }:
{
  config.docker-compose.services = {

    node =  { config, pkgs, ... }: {

      nixos.configuration = {config, pkgs, ...}: (import ../nixos) // {
        boot.isContainer = true;
        
        services.jormungandr = {
          enable = true;
          block0 = ../block-0.bin;
        };
        
        system.build.run-jormungandr = pkgs.writeScript "run-jormungandr" ''
            #!${pkgs.bash}/bin/bash
            PATH='${config.systemd.services.jormungandr.environment.PATH}'
            echo jormungandr:x:${toString config.users.users.jormungandr.uid}:${toString config.users.groups.jormungandr.gid}:jormungandr node daemon user:/var/empty:/bin/sh >>/etc/passwd
            echo jormungandr:x:${toString config.users.groups.jormungandr.gid}:jormungandr >>/etc/group
            ${config.systemd.services.jormungandr.runner}
        '';
      };
      service.command = [ config.nixos.build.run-jormungandr ];
      service.useHostStore = true;
      service.ports = [
        "8607:8607" # host:container
      ];
    };
  };
}