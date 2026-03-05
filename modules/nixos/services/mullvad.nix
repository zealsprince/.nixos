{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.services.mullvad;
in
{
  options.my.services.mullvad = {
    enable = lib.mkEnableOption "Mullvad VPN system daemon (mullvad-daemon)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.mullvad-vpn;
      description = ''
        Mullvad VPN package to install.

        This should provide the CLI (`mullvad`) and the daemon (`mullvad-daemon`).
      '';
    };

    startAtBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to start Mullvad daemon automatically at boot (multi-user target).";
    };

    # Optional: some setups use a specific group to allow non-root control.
    # Keep off by default; NixOS upstream module (if present) may already handle this.
    allowNonRoot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to allow non-root users to control Mullvad via group permissions.

        If enabled, this module creates a `mullvad` group and adds your configured
        users to it. (You must set `users` accordingly.)
      '';
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Users to add to the `mullvad` group when `allowNonRoot = true`.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = [ cfg.package ];

        # Prefer upstream NixOS module if it exists in your nixpkgs.
        # If not present, the fallback unit below will be used.
        services.mullvad-vpn = {
          enable = lib.mkDefault true;
          package = lib.mkDefault cfg.package;
        };

        # Ensure iproute2 is available in the mullvad-daemon service PATH.
        #
        # The userspace WireGuard implementation (used when DAITA is enabled) may
        # call `ip` to configure network interfaces or set IPv6 addresses on newly
        # created TUN devices. Without iproute2 in PATH the daemon fails with:
        #   "Failed to set IPv6 address — No such file or directory (os error 2)"
        systemd.services.mullvad-daemon.path = lib.mkAfter [ pkgs.iproute2 ];
      }

      # Fallback service for nixpkgs builds that don't provide `services.mullvad-vpn`.
      #
      # We guard on the upstream module NOT being enabled so both definitions
      # never collide — the `systemd.services.mullvad-daemon` attrset above only
      # sets `path`, while this block sets the full unit description. They live in
      # separate lib.mkMerge list items so Nix never sees them as duplicate keys.
      (lib.mkIf (!config.services.mullvad-vpn.enable) {
        systemd.services.mullvad-daemon = {
          description = "Mullvad VPN daemon (fallback unit)";
          documentation = [ "https://mullvad.net/" ];

          wantedBy = lib.mkIf cfg.startAtBoot [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          serviceConfig = {
            Type = "simple";
            ExecStart = "${cfg.package}/bin/mullvad-daemon";
            Restart = "on-failure";
            RestartSec = "2s";

            # The daemon manages networking/routing; run as root.
            User = "root";
            Group = "root";
          };
        };
      })

      (lib.mkIf cfg.allowNonRoot {
        users.groups.mullvad = { };

        users.users = builtins.listToAttrs (
          map (u: {
            name = u;
            value = {
              extraGroups = [ "mullvad" ];
            };
          }) cfg.users
        );
      })
    ]
  );
}
