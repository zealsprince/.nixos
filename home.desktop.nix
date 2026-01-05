{ config, pkgs, lib, inputs ? null, ... }:

{
  imports = [
    # Base (CLI/portable) profile
    ./home.nix

    # Desktop additions
    ./modules/home/packages/desktop.nix

    # AMD-specific desktop extras (kept separate; enable is host-controlled)
    ./modules/home/packages/desktop.amd.nix

    # WM-specific config (Plasma 6)
    ./modules/home/wm/plasma6.nix
  ];

  # ---------------------------------------------------------------------------
  # Desktop (GUI) user package set
  # ---------------------------------------------------------------------------
  my.home.packages.desktop.enable = true;

  # NOTE:
  # Do NOT enable AMD-specific packages here. Keep this profile vendor-agnostic.
  # Enable on the AMD desktop host only, e.g.:
  #   my.home.packages.desktop.amd.enable = true;

  # ---------------------------------------------------------------------------
  # Plasma 6 (WM-specific Home Manager config)
  # ---------------------------------------------------------------------------
  my.home.wm.plasma6 = {
    enable = true;

    kwinRules = {
      enable = true;
      rulesFile = ./hosts/ANDREW-DREAMREAPER/layout.kwinrule;
    };

    autostart = {
      enable = true;

      dropbox.enable = true;

      # Yakuake: autostart hidden (tray) and toggle via Ctrl+;
      yakuake = {
        enable = true;
        hideWindow = false;
      };

      # Spectacle: don't take a screenshot on startup; register on DBus.
      spectacle.enable = true;

      # 1Password: start to tray
      onePassword = {
        enable = true;
        silent = true;
      };

      # Start these apps silently (minimized/hidden) on Plasma login
      steam.enable = true;
      discord.enable = true;

      opensnitchUi.enable = true;
      qpwgraph.enable = true;
      mullvadVpn.enable = true;
      slack.enable = true;
      teams.enable = true;

      # FlexDesigner: start silently and keep it in the tray (best-effort)
      flexDesigner = {
        enable = true;
        delaySeconds = 2;
      };
    };

    shortcuts = {
      enable = true;

      spectacle = {
        enable = true;

        activeWindow = "Ctrl+Meta+@";
        fullscreen = "Ctrl+Meta+!";
        rectangularRegion = "Ctrl+Meta+$";

        # Disabled by default to match the intended defaults.
        currentMonitor = null;
        windowUnderCursor = null;
        launchWithoutScreenshot = null;
        launch = null;

        startStopRegionRecording = "Ctrl+Meta+%";
        startStopScreenRecording = [ "Meta+Alt+R" "Ctrl+Meta+^" ];
        startStopWindowRecording = "Meta+Ctrl+R";
      };

      yakuake = {
        enable = true;
        toggle = "Ctrl+;";
      };
    };

    yakuake = {
      configureWindow = true;
      height = 40;
      width = 49;
      x = 1;
    };

    restartKglobalAccel = true;
  };
}
