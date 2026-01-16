{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.services.virtuosoSidetone;

  amixer = "${pkgs.alsa-utils}/bin/amixer";
  sleep = "${pkgs.coreutils}/bin/sleep";
  seq = "${pkgs.coreutils}/bin/seq";

  # Clamp sidetone level to Virtuoso's observed range (0-23).
  clampLevel =
    level:
    let
      l = if level < 0 then 0 else level;
    in
    if l > 23 then 23 else l;

  # Write a real script file so systemd ExecStart doesn't have to embed complex quoting.
  applyScriptFile = pkgs.writeShellScript "virtuoso-sidetone-apply" ''
    set -euo pipefail

    # Prefer targeting the ALSA card *id* (stable) rather than parsing card numbers
    # or relying on /proc/asound/cards formatting/timing.
    card="Gamin"

    # If the headset isn't connected, exit quickly and cleanly so rebuilds don't fail.
    if [ ! -d "/proc/asound/$card" ]; then
      echo "Virtuoso ALSA card '$card' not present; skipping" >&2
      exit 0
    fi

    # ALSA control enumeration can lag behind the udev event that triggers this service.
    # Wait briefly until the Sidetone control is available on the Virtuoso card.
    for _ in $(${seq} 1 8); do
      if ${amixer} -c "$card" sget Sidetone >/dev/null 2>&1; then
        ${amixer} -c "$card" sset Sidetone on
        ${amixer} -c "$card" sset Sidetone ${toString (clampLevel cfg.level)}
        exit 0
      fi
      ${sleep} 0.25
    done

    echo "Virtuoso ALSA card '$card' present but Sidetone control not available (after waiting)" >&2
    exit 0
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
        TimeoutStartSec = 2;
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
