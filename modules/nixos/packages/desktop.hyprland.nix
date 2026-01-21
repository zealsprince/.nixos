{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.desktop.hyprland;
in
{
  /*
    Hyprland-specific desktop packages.

    Intent:
    - Keep Hyprland-only utilities (bars, lockers, wallpaper daemons) out of
      the generic desktop set.
    - Gate everything behind `my.desktop.hyprland.enable` so hosts can enable
      Hyprland support without manually listing every utility.

    Notes:
    - This module is only for *packages*. Hyprland session/service configuration
      belongs in `modules/nixos/desktop/hyprland.nix`.
  */

  options.my.desktop.hyprland = {
    enableSwaync = lib.mkEnableOption "Install swaynotificationcenter (swaync) notification center";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      (with pkgs; [
        # --- File browser ---
        nautilus

        # --- Status Bar ---
        waybar

        # --- Launcher ---
        rofi

        # --- Wallpaper ---
        hyprpaper

        # --- Idle & Locking ---
        hypridle
        hyprlock

        # --- Screenshot / Recording ---
        grim # Grab images from Wayland compositor
        slurp # Select region for grim
        swappy # Snapshot editing tool

        # --- Clipboard ---
        wl-clipboard
        cliphist

        # --- Color Picker ---
        hyprpicker

        # --- System Tray Utilities ---
        networkmanagerapplet
      ])
      ++ lib.optionals cfg.enableSwaync (
        with pkgs;
        [
          # --- Notifications ---
          # NOTE: swaync competes with Plasma's notification daemon via DBus, so keep this opt-in.
          swaynotificationcenter # "swaync" - provides a nice control center
        ]
      );
  };
}
