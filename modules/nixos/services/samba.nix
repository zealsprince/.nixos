{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.services.samba;
in
{
  options.my.services.samba = {
    enable = lib.mkEnableOption "Samba file sharing support (needed for Dolphin sharing tab)";
  };

  config = lib.mkIf cfg.enable {
    # =========================================================================
    # Samba Service
    # =========================================================================
    services.samba = {
      enable = true;
      openFirewall = true;

      settings = {
        global = {
          "workgroup" = "WORKGROUP";
          "server string" = "${config.networking.hostName}";
          "netbios name" = "${config.networking.hostName}";
          "security" = "user";

          # Optimizations
          "hosts allow" = "192.168.0. 192.168.1. 127.0.0.1 localhost";
          "hosts deny" = "0.0.0.0/0";
          "guest account" = "nobody";
          "map to guest" = "bad user";

          # =================================================================
          # Usershare Settings (Dolphin Integration)
          # =================================================================
          # This allows non-root users to create shares via the GUI.
          "usershare path" = "/var/lib/samba/usershares";
          "usershare max shares" = 100;
          "usershare allow guests" = "yes";
          "usershare owner only" = "no";
        };
      };
    };

    # =========================================================================
    # Web Services Dynamic Discovery (WSDD)
    # =========================================================================
    # Makes this host visible in the Windows "Network" tab.
    services.samba-wsdd = {
      enable = true;
      openFirewall = true;
    };

    # =========================================================================
    # Directory Permissions
    # =========================================================================
    # Create the usershare directory with permissions that allow the 'sambashare'
    # group to create/modify share definitions.
    users.groups.sambashare = { };

    systemd.tmpfiles.rules = [
      "d /var/lib/samba/usershares 1770 root sambashare - -"
    ];

    # Add the necessary package for the CLI tools usually expected by the GUI
    environment.systemPackages = [ pkgs.samba ];
  };
}
