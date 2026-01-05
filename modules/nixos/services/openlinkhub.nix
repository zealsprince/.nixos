{ config, lib, pkgs, ... }:

let
  cfg = config.my.services.openlinkhub;

  # Keep this in sync with the nixpkgs package version you’re using.
  # This module seeds runtime assets from the upstream repo at the same tag.
  version = "0.6.9";

  upstreamSource = pkgs.fetchFromGitHub {
    owner = "jurkovic-nikola";
    repo = "OpenLinkHub";
    tag = version;

    # Must match nixpkgs `pkgs.openlinkhub.src` hash for this version.
    # If nixpkgs bumps, update `version` + `hash` together.
    hash = "sha256-5y1G5RUYsuHIUyoZEF9uUxq8sN6lQqXjpatBqkzlO4w=";
  };

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

        # --------------------------------------------------------------------
        # Seed OpenLinkHub runtime assets (one-time).
        #
        # OpenLinkHub expects these directories to exist relative to ConfigPath:
        #   - database/ (language, keyboard definitions, etc.)
        #   - web/      (templates/*.html)
        #   - static/   (css/js/images; served from ./static)
        #
        # Many modules fatally error if they cannot read these folders.
        # --------------------------------------------------------------------

        mkdir -p "$STATE_DIR/database" "$STATE_DIR/web" "$STATE_DIR/static"

        if [ ! -e "$STATE_DIR/database/.openlinkhub-seeded" ]; then
          cp -a ${upstreamSource}/database/. "$STATE_DIR/database/"
          touch "$STATE_DIR/database/.openlinkhub-seeded"
        fi

        if [ ! -e "$STATE_DIR/web/.openlinkhub-seeded" ]; then
          cp -a ${upstreamSource}/web/. "$STATE_DIR/web/"
          touch "$STATE_DIR/web/.openlinkhub-seeded"
        fi

        if [ ! -e "$STATE_DIR/static/.openlinkhub-seeded" ]; then
          cp -a ${upstreamSource}/static/. "$STATE_DIR/static/"
          touch "$STATE_DIR/static/.openlinkhub-seeded"
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
