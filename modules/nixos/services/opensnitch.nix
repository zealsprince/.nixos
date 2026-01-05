{ config, lib, pkgs, ... }:

let
  cfg = config.my.services.opensnitch;
in
{
  options.my.services.opensnitch = {
    enable = lib.mkEnableOption "OpenSnitch firewall application daemon (opensnitchd)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.opensnitch;
      description = "Which OpenSnitch package to install/provide (must include opensnitchd).";
    };

    # Most people want OpenSnitch active at boot, but this keeps parity with your other service modules.
    startAtBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to start OpenSnitch daemon automatically at boot (multi-user target).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Prefer upstream NixOS module if it exists in your nixpkgs.
    # If not present, the fallback unit below will be used.
    services.opensnitch.enable = lib.mkDefault true;

    systemd.services.opensnitchd = lib.mkIf (!config.services.opensnitch.enable) {
      description = "OpenSnitch daemon (fallback unit)";
      documentation = [ "https://github.com/evilsocket/opensnitch" ];

      wantedBy = lib.mkIf cfg.startAtBoot [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/opensnitchd";
        Restart = "on-failure";
        RestartSec = "2s";

        # OpenSnitch needs privileges to interface with firewall/packet filtering.
        User = "root";
        Group = "root";
      };
    };
  };
}
