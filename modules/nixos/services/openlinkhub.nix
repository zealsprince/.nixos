{ config, lib, pkgs, ... }:

let
  cfg = config.my.services.openlinkhub;

  # Minimal safety net for the earliest bootstrapping; once upstream database is copied,
  # it will likely already provide this file.
  defaultRgbJson = pkgs.writeText "openlinkhub-rgb.json" ''
    {
      "defaultColor": {
        "red": 255,
        "green": 100,
        "blue": 0,
        "brightness": 1
      },
      "profiles": {
        "custom": {},
        "keyboard": {},
        "mouse": {},
        "headset": {},
        "controller": {},
        "stand": {},
        "mousepad": {}
      }
    }
  '';
in
{
  options.my.services.openlinkhub = {
    enable = lib.mkEnableOption "OpenLinkHub system service (runs as root; state under /var/lib/openlinkhub)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.openlinkhub;
      description = "Which OpenLinkHub package to run.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/openlinkhub";
      description = "Persistent state directory used as OpenLinkHub working directory/config root.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the configured listen port in the firewall (TCP).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Optional, only if you want to access from other machines.
    # Default OpenLinkHub config listens on 127.0.0.1:27003.
    networking.firewall.allowedTCPPorts =
      lib.mkIf cfg.openFirewall [ 27003 ];

    systemd.services.openlinkhub = {
      description = "OpenLinkHub (Corsair iCUE LINK Hub controller)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";

        # OpenLinkHub computes ConfigPath and asset paths using os.Getwd().
        # We pin the working directory to its persistent state directory.
        WorkingDirectory = cfg.stateDir;

        # Have systemd create/manage the state directory under /var/lib.
        # NOTE: When cfg.stateDir is the default (/var/lib/openlinkhub), StateDirectory
        # aligns with WorkingDirectory. If you change cfg.stateDir, keep these consistent.
        StateDirectory = "openlinkhub";
        StateDirectoryMode = "0755";

        ExecStart = "${cfg.package}/bin/OpenLinkHub";

        Restart = "on-failure";
        RestartSec = "2s";

        # Start with the pragmatic approach: run as root for device access.
        # You can harden later (udev rules + user service, or capabilities).
        User = "root";
        Group = "root";
      };

      preStart = ''
        set -euo pipefail

        STATE_DIR="${cfg.stateDir}"

        # Seed assets straight from the package we run, so they always match the
        # binary. The assets live under opt/OpenLinkHub in the nixpkgs package.
        ASSETS="${cfg.package}/opt/OpenLinkHub"

        # Marker carries the exact package store path. When the package changes,
        # this stops matching and we re-sync. Pinning a separate source by version
        # is what let static/ drift out of sync and panic loadThemes() on upgrade.
        TOKEN="${cfg.package}"
        MARKER="$STATE_DIR/.seeded-version"

        # --------------------------------------------------------------------
        # OpenLinkHub expects these directories relative to its working dir:
        #   - database/ (language, keyboard/device definitions, runtime state)
        #   - web/      (templates/*.html)
        #   - static/   (css/js/images, including css/themes; served from ./static)
        #
        # Many modules fatally error if they cannot read these folders.
        # --------------------------------------------------------------------

        mkdir -p "$STATE_DIR/database" "$STATE_DIR/web" "$STATE_DIR/static"

        if [ "$(cat "$MARKER" 2>/dev/null || true)" != "$TOKEN" ]; then
          # static/ and web/ are immutable assets owned by the package. Replace
          # them wholesale so a newer binary never reads a stale layout.
          rm -rf "$STATE_DIR/static" "$STATE_DIR/web"
          mkdir -p "$STATE_DIR/static" "$STATE_DIR/web"
          cp -a "$ASSETS/static/." "$STATE_DIR/static/"
          cp -a "$ASSETS/web/." "$STATE_DIR/web/"
          chmod -R u+w "$STATE_DIR/static" "$STATE_DIR/web"

          # database/ mixes shipped defaults with runtime state, so only add new
          # files (e.g. new device definitions) without clobbering user data.
          cp -an "$ASSETS/database/." "$STATE_DIR/database/" || true
          chmod -R u+w "$STATE_DIR/database"

          echo "$TOKEN" > "$MARKER"
        fi

        # Ensure user-writable subdirs exist even if upstream layout changes.
        mkdir -p "$STATE_DIR/database/temperatures" "$STATE_DIR/database/macros"

        # Safety net for rgb.json (older failures were caused by missing or empty files).
        if [ ! -f "$STATE_DIR/database/rgb.json" ]; then
          install -m 0644 ${defaultRgbJson} "$STATE_DIR/database/rgb.json"
        fi

        # Ensure config.json exists; OpenLinkHub will auto-create/upgrade it if missing.
        # We don’t write it here to avoid pinning defaults in Nix; it’s runtime state.
        true
      '';
    };
  };
}
