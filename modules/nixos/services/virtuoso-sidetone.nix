{ config, lib, pkgs, ... }:

let
  cfg = config.my.services.virtuosoSidetone;

  bash = "${pkgs.bash}/bin/bash";
  grep = "${pkgs.gnugrep}/bin/grep";
  head = "${pkgs.coreutils}/bin/head";
  awk = "${pkgs.gawk}/bin/awk";
  amixer = "${pkgs.alsa-utils}/bin/amixer";

  # Clamp sidetone level to Virtuoso's observed range (0-23).
  clampLevel = level:
    let
      l = if level < 0 then 0 else level;
    in
    if l > 23 then 23 else l;

  # Write a real script file so systemd ExecStart doesn't have to embed complex quoting.
  applyScriptFile = pkgs.writeShellScript "virtuoso-sidetone-apply" ''
    set -euo pipefail

    line="$(${grep} -m1 "VIRTUOSO" /proc/asound/cards || true)"
    if [ -z "$line" ]; then
      echo "Virtuoso ALSA card not found in /proc/asound/cards" >&2
      exit 0
    fi

    card="$(printf '%s\n' "$line" | ${awk} '{print $1}')"
    if ! printf '%s' "$card" | ${grep} -Eq '^[0-9]+$'; then
      echo "Failed to parse Virtuoso ALSA card number from line: $line" >&2
      exit 1
    fi

    ${amixer} -c "$card" sset Sidetone on
    ${amixer} -c "$card" sset Sidetone ${toString (clampLevel cfg.level)}
  '';
in
{
  options.my.services.virtuosoSidetone = {
    enable = lib.mkEnableOption "Re-apply Corsair Virtuoso hardware sidetone whenever the USB device shows up (udev-triggered system service).";

    level = lib.mkOption {
      type = lib.types.int;
      default = 23;
      description = "Sidetone level to set (Virtuoso range is 0-23). Values outside will be clamped.";
      example = 23;
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure `amixer` is present (useful interactively too).
    environment.systemPackages = [ pkgs.alsa-utils ];

    # When the Virtuoso USB device appears/reconnects, udev will trigger this service.
    systemd.services.virtuoso-sidetone = {
      description = "Set Corsair Virtuoso sidetone (ALSA amixer) on device add/change";
      wantedBy = [ "multi-user.target" ];

      # Keep it robust: if the headset isn't present yet in ALSA, don't hang.
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = 10;
        ExecStart = "${applyScriptFile}";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    # NOTE:
    # Udev triggers live in the host config (e.g. `hosts/ANDREW-DREAMREAPER/default.nix`)
    # so we don't conflict with other `services.udev.extraRules` definitions.
  };
}
