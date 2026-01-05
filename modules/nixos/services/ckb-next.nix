{ lib, config, pkgs, ... }:

let
  cfg = config.my.services.ckb-next;

  # Use a consistent ckb-next derivation everywhere (systemPackages, udev rules,
  # and the daemon itself) so we don't accidentally build different variants.
  ckbNextPkg = pkgs.ckb-next.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DUSE_DBUS_MENU=0" ];
  });
in
{
  options.my.services.ckb-next = {
    enable = lib.mkEnableOption "ckb-next daemon (Corsair keyboard/mouse support)";
  };

  config = lib.mkIf cfg.enable {
    # Some nixpkgs revisions don't ship a NixOS module at `services.ckb-next`.
    # In that case, define the systemd unit ourselves and make sure required
    # runtime deps (udev rules, binary) are present.
    #
    # Note: This assumes the derivation provides the `ckb-next-daemon` binary.
    environment.systemPackages = [ ckbNextPkg ];

    services.udev.packages = [ ckbNextPkg ];

    systemd.services.ckb-next-daemon = {
      description = "ckb-next daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-udevd.service" "syslog.target" ];
      wants = [ "systemd-udevd.service" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${ckbNextPkg}/bin/ckb-next-daemon";
        Restart = "on-failure";
        RestartSec = 2;

        # ckb-next needs access to hidraw and usb devices; upstream typically runs as root.
        User = "root";
        Group = "root";

        # Hardening (keep conservative to avoid breaking device access)
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = false;
        ProtectControlGroups = true;
        LockPersonality = true;
        RestrictSUIDSGID = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
      };
    };
  };
}
