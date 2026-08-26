{
  inputs,
  pkgs,
  lib,
  ...
}:

let
  gsrNotify = pkgs.writeShellScript "gsr-notify" ''
    VIDEO=$1
    MODE=$2

    case "$MODE" in
      "replay") MSG="Replay saved" ;;
      "regular") MSG="Recording saved" ;;
      "screenshot") MSG="Screenshot saved" ;;
      *) MSG="Saved" ;;
    esac

    ${pkgs.libnotify}/bin/notify-send -a "GPU Screen Recorder" "$MSG" "$VIDEO"
  '';
in
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

    # Dolphin "Convert To" service menus (images, video, audio)
    ./modules/home/wm/plasma6.convert.nix

    # WM-specific config (Hyprland)
    ./modules/home/wm/hyprland.nix
  ];

  # ---------------------------------------------------------------------------
  # Zen Browser
  # ---------------------------------------------------------------------------
  # Inject the portal file-picker pref into all Zen profiles so the KDE native
  # file dialog is used instead of the GTK one.
  home.activation.zenPortalFilePicker = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -d "$HOME/.zen" ]; then
      for profile in "$HOME/.zen"/*/; do
        # Skip non-profile dirs (e.g. Profile Groups)
        [ -f "$profile/prefs.js" ] || continue
        userjs="$profile/user.js"
        pref='user_pref("widget.use-xdg-desktop-portal.file-picker", 1);'
        if ! grep -qF 'widget.use-xdg-desktop-portal.file-picker' "$userjs" 2>/dev/null; then
          echo "$pref" >> "$userjs"
        fi
      done
    fi
  '';

  # Zed Editor Theme
  home.file.".config/zed/themes/neko-dark.json".source =
    inputs.neko-zed-dark + "/themes/neko-dark.json";

  # ---------------------------------------------------------------------------
  # Desktop (GUI) user package set
  # ---------------------------------------------------------------------------
  my.home.packages.desktop.enable = true;

  # ---------------------------------------------------------------------------
  # Hyprland theming (consume hyprlands into ~/.config/*)
  #
  # This does not start Hyprland; it only links theme folders/files into place.
  # ---------------------------------------------------------------------------
  my.home.wm.hyprland = {
    enable = true;

    theme = {
      enable = true;
      source = inputs.hyprlands + "/themes/cobalt";

      # Or use a local path for development:
      # source = "/home/zealsprince/Projects/zealsprince/hyprlands/themes/cobalt";
      # dev.enable = true;

      # hyprlands includes these folders already
      consume = {
        hypr = true;
        waybar = true;
        gtk3 = false;
        gtk4 = false;
        kitty = true;
        fastfetch = true;
        rofi = true;
        waypaper = true;
      };
    };
  };

  # NOTE:
  # Do NOT enable AMD-specific packages here. Keep this profile vendor-agnostic.
  # Enable on the AMD desktop host only, e.g.:
  #   my.home.packages.desktop.amd.enable = true;

  # ---------------------------------------------------------------------------
  # Plasma 6 (WM-specific Home Manager config)
  # ---------------------------------------------------------------------------
  my.home.wm.plasma6 = {
    enable = true;

    autostart = {
      enable = true;

      ckbNext.enable = true;

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
      ferdium.enable = true;

      # Deskflow: launch to tray; its own "start core with GUI" setting brings
      # the server up (it will still show the input capture portal dialog once
      # per session, no way around that until Deskflow 1.27 + newer Plasma).
      deskflow.enable = true;

      # FlexDesigner: start silently and keep it in the tray (best-effort)
      flexDesigner = {
        enable = false;
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
        startStopScreenRecording = [
          "Meta+Alt+R"
          "Ctrl+Meta+^"
        ];
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
      width = 50;
      position = 50;
    };

    restartKglobalAccel = true;

    # Right-click "Convert To" in Dolphin. Defaults cover the formats I actually
    # hit (HEIC off the phone, WebP off the web); trim the lists to shorten the
    # menu.
    convert = {
      enable = true;

      image = {
        enable = true;
        quality = 92;
        formats = [
          "jpg"
          "png"
          "webp"
          "avif"
          "heic"
          "tiff"
          "pdf"
        ];
      };

      video = {
        enable = true;
        crf = 20;
        formats = [
          "mp4"
          "mkv"
          "webm"
          "gif"
          "mp3"
        ];
      };

      audio = {
        enable = true;
        bitrate = "320k";
        formats = [
          "mp3"
          "flac"
          "wav"
          "opus"
          "m4a"
        ];
      };
    };
  };

  # Manual Shortcuts (Plasma):
  #   Alt+F9  : systemctl --user kill --signal=SIGRTMIN gpu-screen-recorder-replay  (Toggle Recording)
  #   Alt+F10 : systemctl --user kill --signal=SIGUSR1 gpu-screen-recorder-replay   (Save Replay)
  systemd.user.services.gpu-screen-recorder-replay = {
    Unit = {
      Description = "GPU Screen Recorder replay buffer";
      After = [ "graphical-session.target" ];
      Wants = [ "graphical-session.target" ];
    };
    Service = {
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/Videos/replays %h/Videos/recordings";
      ExecStart = "${pkgs.bash}/bin/bash -c 'if [ -x /run/wrappers/bin/gpu-screen-recorder ]; then exec /run/wrappers/bin/gpu-screen-recorder \"$@\"; else exec ${pkgs.gpu-screen-recorder}/bin/gpu-screen-recorder \"$@\"; fi' -- -v no -w portal -restore-portal-session yes -c mp4 -k hevc_hdr -cr full -f 120 -r 120 -o %h/Videos/replays -ro %h/Videos/recordings -a default_output -a default_input -sc ${gsrNotify}";
      KillSignal = "SIGINT";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
