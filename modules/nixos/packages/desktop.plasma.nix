{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

let
  plasmaEnabled = config.my.desktop.plasma6.enable or false;
in
{
  /*
    Plasma-specific desktop packages.

    Intent:
    - Keep KDE/Plasma-only applications out of the generic desktop packages set.
    - Gate everything behind `my.desktop.plasma6.enable` so hosts can switch to a
      different compositor/DE (Hyprland, sway, etc.) without pulling KDE apps.

    Notes:
    - This module is only for *packages*. Plasma session/service configuration
      belongs in `modules/nixos/desktop/plasma6.nix`.
  */

  config = lib.mkIf plasmaEnabled {
    environment.systemPackages = with pkgs; [
      # KDE/Plasma utilities
      kdePackages.yakuake

      # Disk usage analyzer
      kdePackages.filelight
      kdePackages.kdenetwork-filesharing
      kdePackages.kio
      kdePackages.kio-fuse
      kdePackages.kio-extras
      kdePackages.purpose
      kdePackages.kdeconnect-kde
      kdePackages.kaccounts-integration
      kdePackages.kaccounts-providers

      # Need a calculator
      kdePackages.kalk

      # Pinentry UI that fits KDE/Qt environments
      pinentry-qt

      # KWin Force Blur
      inputs.kwin-effects-forceblur.packages.${pkgs.stdenv.hostPlatform.system}.default # Wayland
      inputs.kwin-effects-forceblur.packages.${pkgs.stdenv.hostPlatform.system}.x11 # X11
    ];
  };
}
