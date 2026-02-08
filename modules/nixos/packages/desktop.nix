{
  pkgs,
  lib,
  inputs ? { },
  ...
}:

{
  /*
    Desktop-focused system packages (DE-agnostic).

    Intent:
    - Put GUI applications and desktop-only tooling here so a terminal-only
      system can avoid pulling them in.
    - Keep this module safe to use with any desktop environment / window manager
      (Plasma, Hyprland, GNOME, etc.).
    - Do not include DE-specific apps here (e.g. KDE/Plasma utilities). Those
      should live in a dedicated module like `packages/desktop.plasma.nix`.

    Notes:
    - `inputs` is optional; we only use it when provided (e.g. zen-browser flake).

    Windows apps (WinApps-style):
    - If you enable `my.virtualisation.winapps.enable`, this desktop module will
      pull in the WinApps-style integration (libvirt/KVM + FreeRDP launchers).
    - Setup documentation lives in `modules/nixos/virtualisation/winapps.nix`
      (options are self-documented there via descriptions).
  */

  imports = [
    ../virtualisation/winapps.nix
  ];

  # services.udev.packages = with pkgs; [
  #   headsetcontrol
  # ];

  environment.systemPackages =
    (with pkgs; [
      # Control Corsair Devices
      (ckb-next.overrideAttrs (old: {
        cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DUSE_DBUS_MENU=0" ];
      }))
      openlinkhub
      openrgb-with-all-plugins
      # headsetcontrol

      # Desktop!
      linux-wallpaperengine

      # Media / utilities commonly expected on desktop
      mpv
      simple-scan

      # Security
      opensnitch
      mullvad-vpn

      # PipeWire patchbay (visual audio routing)
      qpwgraph
      open-music-kontrollers.patchmatrix
      easyeffects
      pipewire

      # Terminal emulators (desktop preference)
      alacritty
      kitty

      # Bluetooth tooling (CLI utilities)
      bluez
      bluez-tools
    ])
    ++ (lib.optionals (inputs ? zen-browser) [
      inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    ]);
}
