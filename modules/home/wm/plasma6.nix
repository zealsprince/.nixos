{ config, pkgs, lib, ... }:

let
  cfg = config.my.home.wm.plasma6;

  # Keep ckb-next build consistent with the system configuration:
  # disable dbusmenu-qt5 so the GUI can build even when dbusmenu-qt5 isn't available.
  ckbNextPkg = pkgs.ckb-next.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DUSE_DBUS_MENU=0" ];
  });

  kwriteconfig = "${pkgs.kdePackages.kconfig}/bin/kwriteconfig6";

  mkAutostartDesktop = { name, exec, startupNotify ? false }:
    ''
      [Desktop Entry]
      Type=Application
      Name=${name}
      Exec=${exec}
      Terminal=false
      StartupNotify=${if startupNotify then "true" else "false"}
    '';

  # Run in the background, don't inherit startup activation, and hide from UI lists.
  #
  # Note: This does not guarantee an app is minimized; it only launches it in a way
  # that tends to avoid focus-stealing and keeps it out of autostart UIs.
  mkAutostartDesktopHidden = { name, exec, startupNotify ? false }:
    ''
      [Desktop Entry]
      Type=Application
      Name=${name}
      Exec=${pkgs.runtimeShell} -lc '${exec} >/dev/null 2>&1 & disown'
      Terminal=false
      StartupNotify=${if startupNotify then "true" else "false"}
      NoDisplay=true
    '';

  # Wayland-safe post-login "close to tray" helper (using kdotool).
  #
  # Why: during Plasma Wayland startup, some apps (notably Electron/Qt) map/raise a window
  # briefly even if you try to start them “hidden”. KWin rules can also be timing-sensitive.
  #
  # Strategy:
  #   1) wait a short initial delay for the session + tray to fully come up
  #   2) poll briefly for matching windows
  #   3) close the window (apps configured for “close to tray” will hide into the tray)
  #   4) write a small log so you can confirm which windows were acted on
  mkPostLoginWindowHandlerScript = {
    closeClasses ? [],
    minimizeClasses ? [],
    attempts ? 120,
    sleepSeconds ? 0.5,
    initialDelaySeconds ? 3,
    closeDelaySeconds ? 1,
    ...
  }:
    let
      closeRegex = "(" + (lib.concatStringsSep "|" (map lib.escapeRegex closeClasses)) + ")";
      minimizeRegex = "(" + (lib.concatStringsSep "|" (map lib.escapeRegex minimizeClasses)) + ")";
      hasClose = closeClasses != [];
      hasMinimize = minimizeClasses != [];
    in
      pkgs.writeShellScript "plasma6-post-login-window-handler" ''
        set -eu

        # Use fallback for XDG_STATE_HOME to prevent unbound variable errors
        STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/plasma6"
        LOG_FILE="$STATE_DIR/post-login-window-handler.log"
        KDOTOOL="${pkgs.kdotool}/bin/kdotool"

        mkdir -p "$STATE_DIR" 2>/dev/null || true

        log() {
          echo "[$(date -Iseconds)] $*" >>"$LOG_FILE" 2>/dev/null || true
        }

        log "starting post-login window handler"
        log "  initialDelaySeconds=${toString initialDelaySeconds} attempts=${toString attempts}"

        # Give Plasma a moment to finish bringing up the panel/tray.
        sleep ${toString initialDelaySeconds}

        i=0
        # Track processed classes to avoid re-closing windows if the user re-opens them
        processed_classes=" "

        while [ "$i" -lt ${toString attempts} ]; do

          # 1. Close list
          ${lib.optionalString hasClose ''
          ids_c="$($KDOTOOL search --class '${closeRegex}' 2>/dev/null || true)"
          batch_classes=""

          if [ -n "''${ids_c}" ]; then
            while IFS= read -r id; do
              [ -n "''${id}" ] || continue

              c="$($KDOTOOL getwindowclassname "''${id}" 2>/dev/null || true)"

              # Check if class already processed globally
              case "''${processed_classes}" in
                *" ''${c} "*) continue ;;
              esac

              # Track class for update after this batch
              batch_classes="''${batch_classes}''${c} "

              t="$($KDOTOOL getwindowname "''${id}" 2>/dev/null || true)"
              log "CLOSING id=''${id} class=''${c} title=''${t}"

              sleep ${toString closeDelaySeconds}
              $KDOTOOL windowclose "''${id}" >/dev/null 2>&1 || true
            done <<< "''${ids_c}"

            # Update processed classes
            processed_classes="''${processed_classes}''${batch_classes}"
          fi
          ''}

          # 2. Minimize list
          ${lib.optionalString hasMinimize ''
          ids_m="$($KDOTOOL search --class '${minimizeRegex}' 2>/dev/null || true)"
          batch_classes=""

          if [ -n "''${ids_m}" ]; then
            while IFS= read -r id; do
              [ -n "''${id}" ] || continue

              c="$($KDOTOOL getwindowclassname "''${id}" 2>/dev/null || true)"

              # Check if class already processed globally
              case "''${processed_classes}" in
                *" ''${c} "*) continue ;;
              esac

              # Track class for update after this batch
              batch_classes="''${batch_classes}''${c} "

              t="$($KDOTOOL getwindowname "''${id}" 2>/dev/null || true)"
              log "MINIMIZING id=''${id} class=''${c} title=''${t}"

              sleep ${toString closeDelaySeconds}
              $KDOTOOL windowminimize "''${id}" >/dev/null 2>&1 || true
            done <<< "''${ids_m}"

            # Update processed classes
            processed_classes="''${processed_classes}''${batch_classes}"
          fi
          ''}

          i=$((i + 1))
          sleep ${toString sleepSeconds}
        done

        log "finished post-login window handler"
      '';

  # Convenience helper for apps that don’t have a reliable “start minimized” flag.
  mkAutostartDesktopTray = { name, exec }:
    mkAutostartDesktopHidden { inherit name exec; startupNotify = false; };

  mkKsc = primary: defaultShortcut: description:
    "${primary},${defaultShortcut},${description}";


in
{
  options.my.home.wm.plasma6 = {
    enable = lib.mkEnableOption "Plasma 6 Home Manager module (autostart, KDE global shortcuts, and KDE app tweaks)";

    autostart = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to manage KDE/Plasma autostart desktop entries.";
      };

      ckbNext = {
        enable = lib.mkEnableOption "Autostart ckb-next (tray/background)";
      };

      yakuake = {
        enable = lib.mkEnableOption "Autostart Yakuake";
        hideWindow = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Pass --hide-window to Yakuake on startup (if supported).";
        };
      };

      spectacle = {
        enable = lib.mkEnableOption "Autostart Spectacle in DBus mode";
      };

      onePassword = {
        enable = lib.mkEnableOption "Autostart 1Password (tray)";
        silent = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Start 1Password with --silent so it opens to the system tray.";
        };
      };

      steam = {
        enable = lib.mkEnableOption "Autostart Steam (silent)";
      };

      discord = {
        enable = lib.mkEnableOption "Autostart Discord (silent)";
      };

      slack = {
        enable = lib.mkEnableOption "Autostart Slack (silent)";
      };

      teams = {
        enable = lib.mkEnableOption "Autostart Teams (silent)";
      };

      flexDesigner = {
        enable = lib.mkEnableOption "Autostart FlexDesigner (tray)";
        delaySeconds = lib.mkOption {
          type = lib.types.int;
          default = 2;
          description = "Delay starting FlexDesigner to reduce focus/launch race conditions at login.";
        };
      };

      opensnitchUi = {
        enable = lib.mkEnableOption "Autostart OpenSnitch UI";
      };

      qpwgraph = {
        enable = lib.mkEnableOption "Autostart qpwgraph (PipeWire patchbay)";
      };

      mullvadVpn = {
        enable = lib.mkEnableOption "Autostart Mullvad VPN";
      };

      ferdium = {
        enable = lib.mkEnableOption "Autostart Ferdium";
        minimized = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Start minimized to tray.";
        };
      };
    };

    postLogin = {
      closeClasses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "teams-for-linux" "mullvad vpn" "slack" "qpwgraph" "Ferdium" ];
        description = "List of window classes to close (to tray) shortly after login.";
      };
      minimizeClasses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "List of window classes to minimize shortly after login.";
      };
    };

    shortcuts = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to manage Plasma global shortcuts via kglobalshortcutsrc.";
      };

      spectacle = {
        enable = lib.mkEnableOption "Spectacle shortcuts";

        activeWindow = lib.mkOption {
          type = lib.types.str;
          default = "Ctrl+Meta+@";
          description = "Shortcut for 'Capture Active Window'.";
        };

        fullscreen = lib.mkOption {
          type = lib.types.str;
          default = "Ctrl+Meta+!";
          description = "Shortcut for 'Capture Entire Desktop'.";
        };

        rectangularRegion = lib.mkOption {
          type = lib.types.str;
          default = "Ctrl+Meta+$";
          description = "Shortcut for 'Capture Rectangular Region'.";
        };

        currentMonitor = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Shortcut for 'Capture Current Monitor' (null disables).";
        };

        windowUnderCursor = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Shortcut for 'Capture Window Under Cursor' (null disables).";
        };

        launchWithoutScreenshot = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Shortcut for 'Launch without taking a screenshot' (null disables).";
        };

        launch = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Shortcut for 'Launch' (null disables).";
        };

        startStopRegionRecording = lib.mkOption {
          type = lib.types.str;
          default = "Ctrl+Meta+%";
          description = "Shortcut for 'Start/Stop Region Recording'.";
        };

        # Some setups bind two shortcuts to this action.
        # Plasma stores multiple shortcuts separated by a tab character.
        startStopScreenRecording = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "Meta+Alt+R" "Ctrl+Meta+^" ];
          description = "Shortcuts for 'Start/Stop Screen Recording'. First is primary; additional entries are joined by a tab.";
        };

        startStopWindowRecording = lib.mkOption {
          type = lib.types.str;
          default = "Ctrl+Meta+R";
          description = "Shortcut for 'Start/Stop Window Recording'.";
        };
      };

      yakuake = {
        enable = lib.mkEnableOption "Yakuake shortcuts";
        toggle = lib.mkOption {
          type = lib.types.str;
          default = "Ctrl+;";
          description = "Shortcut for 'Open/Retract Yakuake'.";
        };
      };
    };

    yakuake = {
      configureWindow = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to write Yakuake size settings into yakuakerc.";
      };

      width = lib.mkOption {
        type = lib.types.int;
        default = 50;
        description = "Yakuake window width percentage.";
      };

      height = lib.mkOption {
        type = lib.types.int;
        default = 40;
        description = "Yakuake window height percentage.";
      };

      x = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "Yakuake window X offset in pixels (shift right by increasing).";
      };
    };

    restartKglobalAccel = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to try restarting Plasma's global shortcut daemon after writing shortcuts.";
    };
  };

  config = lib.mkIf cfg.enable {
    # -------------------------------------------------------------------------
    # Autostart entries (KDE reads ~/.config/autostart/*.desktop)
    # -------------------------------------------------------------------------
    home.file = lib.mkMerge [
      (lib.mkIf (cfg.autostart.enable && cfg.autostart.yakuake.enable) {
        ".config/autostart/yakuake.desktop".text =
          mkAutostartDesktop {
            name = "Dropdown Terminal (Yakuake)";
            exec =
              "${pkgs.kdePackages.yakuake}/bin/yakuake"
              + lib.optionalString cfg.autostart.yakuake.hideWindow " --hide-window";
          };
      })

      (lib.mkIf (cfg.autostart.enable && cfg.autostart.spectacle.enable) {
        ".config/autostart/org.kde.spectacle.desktop".text =
          mkAutostartDesktop {
            name = "Spectacle";
            # Important: --background takes a screenshot; --dbus registers for activation
            exec = "${pkgs.kdePackages.spectacle}/bin/spectacle --dbus";
          };
      })

      (lib.mkIf (cfg.autostart.enable && cfg.autostart.onePassword.enable) {
        ".config/autostart/1password.desktop".text =
          mkAutostartDesktopTray {
            name = "1Password";
            exec =
              "${pkgs._1password-gui}/bin/1password"
              + lib.optionalString cfg.autostart.onePassword.silent " --silent";
          };
      })

      (lib.mkIf (cfg.autostart.enable && cfg.autostart.steam.enable) {
        ".config/autostart/steam.desktop".text =
          mkAutostartDesktop {
            name = "Steam";
            exec = "${pkgs.steam}/bin/steam -silent";
          };
      })

      (lib.mkIf (cfg.autostart.enable && cfg.autostart.discord.enable) {
        ".config/autostart/discord.desktop".text =
          mkAutostartDesktop {
            name = "Discord";
            exec = "${pkgs.discord}/bin/discord --start-minimized";
          };
      })

      (lib.mkIf (cfg.autostart.enable && cfg.autostart.slack.enable) {
        ".config/autostart/slack.desktop".text =
          mkAutostartDesktopHidden {
            name = "Slack";
            exec = "${pkgs.slack}/bin/slack";
            startupNotify = false;
          };
      })

      (lib.mkIf (cfg.autostart.enable && cfg.autostart.teams.enable) {
        ".config/autostart/teams.desktop".text =
          mkAutostartDesktopHidden {
            name = "Teams";
            # Note: `teams-for-linux` is typically the Nixpkgs package name;
            # keep this consistent with whatever you have installed.
            exec = "${pkgs.teams-for-linux}/bin/teams-for-linux";
            startupNotify = false;
          };
      })

      (lib.mkIf (cfg.autostart.enable && cfg.autostart.flexDesigner.enable) {
        ".config/autostart/flex-designer.desktop".text =
          mkAutostartDesktopHidden {
            name = "FlexDesigner (Tray)";
            exec = "sleep ${toString cfg.autostart.flexDesigner.delaySeconds}; flex-designer";
            startupNotify = false;
          };
      })

      (lib.mkIf (cfg.autostart.enable && cfg.autostart.opensnitchUi.enable) {
        ".config/autostart/opensnitch-ui.desktop".text =
          mkAutostartDesktopTray {
            name = "OpenSnitch UI";
            exec = "${pkgs.opensnitch-ui}/bin/opensnitch-ui";
          };
      })

      (lib.mkIf (cfg.autostart.enable && cfg.autostart.qpwgraph.enable) {
        ".config/autostart/qpwgraph.desktop".text =
          mkAutostartDesktopTray {
            name = "qpwgraph";
            exec = "${pkgs.qpwgraph}/bin/qpwgraph";
          };
      })

      (lib.mkIf (cfg.autostart.enable && cfg.autostart.mullvadVpn.enable) {
        ".config/autostart/mullvad-vpn.desktop".text =
          mkAutostartDesktopTray {
            name = "Mullvad VPN";
            exec = "${pkgs.mullvad-vpn}/bin/mullvad-vpn";
          };
      })

      (lib.mkIf (cfg.autostart.enable && cfg.autostart.ferdium.enable) {
        ".config/autostart/ferdium.desktop".text =
          mkAutostartDesktopTray {
            name = "Ferdium";
            exec =
              "${pkgs.ferdium}/bin/ferdium"
              + lib.optionalString cfg.autostart.ferdium.minimized " --minimized";
          };
      })

      (lib.mkIf (cfg.autostart.enable && cfg.autostart.ckbNext.enable) {
        ".config/autostart/ckb-next.desktop".text =
          mkAutostartDesktopTray {
            name = "ckb-next";
            exec = "${ckbNextPkg}/bin/ckb-next --background";
          };
      })


    ];

    # -------------------------------------------------------------------------
    # Activation: write KDE config + global shortcuts
    # -------------------------------------------------------------------------
    # -------------------------------------------------------------------------
    # Wayland-safe post-login minimizer for apps that insist on showing a window
    # during autostart (Electron/Qt apps commonly do this on Plasma Wayland).
    # -------------------------------------------------------------------------
    systemd.user.services.plasma6PostLoginWindowHandler =
      lib.mkIf (cfg.postLogin.closeClasses != [] || cfg.postLogin.minimizeClasses != []) {
        Unit = {
          Description = "Plasma 6 post-login window handler for selected apps (Wayland)";
          After = [ "graphical-session.target" ];
          Wants = [ "graphical-session.target" ];
        };
        Service = {
          Type = "simple";
          ExecStart =
            let
              script =
                mkPostLoginWindowHandlerScript {
                  closeClasses = cfg.postLogin.closeClasses;
                  minimizeClasses = cfg.postLogin.minimizeClasses;

                  # Tuned for "apps appear late / tray initializes slowly".
                  initialDelaySeconds = 5;
                  closeDelaySeconds = 2;
                  attempts = 60;
                };
            in
              "${script}";
        };
        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };

    home.activation.configurePlasma6 =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        set -e

        ${lib.optionalString cfg.shortcuts.enable ''
          # ---- Spectacle ----
          ${lib.optionalString cfg.shortcuts.spectacle.enable ''
            ${kwriteconfig} --file kglobalshortcutsrc --group "org.kde.spectacle.desktop" --key "_k_friendly_name" "Spectacle"

            ${kwriteconfig} --file kglobalshortcutsrc --group "org.kde.spectacle.desktop" --key "ActiveWindowScreenShot" \
              "${mkKsc cfg.shortcuts.spectacle.activeWindow cfg.shortcuts.spectacle.activeWindow "Capture Active Window"}"

            ${kwriteconfig} --file kglobalshortcutsrc --group "org.kde.spectacle.desktop" --key "FullScreenScreenShot" \
              "${mkKsc cfg.shortcuts.spectacle.fullscreen cfg.shortcuts.spectacle.fullscreen "Capture Entire Desktop"}"

            ${kwriteconfig} --file kglobalshortcutsrc --group "org.kde.spectacle.desktop" --key "RectangularRegionScreenShot" \
              "${mkKsc cfg.shortcuts.spectacle.rectangularRegion cfg.shortcuts.spectacle.rectangularRegion "Capture Rectangular Region"}"

            ${kwriteconfig} --file kglobalshortcutsrc --group "org.kde.spectacle.desktop" --key "CurrentMonitorScreenShot" \
              "${mkKsc (if cfg.shortcuts.spectacle.currentMonitor == null then "none" else cfg.shortcuts.spectacle.currentMonitor)
                      (if cfg.shortcuts.spectacle.currentMonitor == null then "none" else cfg.shortcuts.spectacle.currentMonitor)
                      "Capture Current Monitor"}"

            ${kwriteconfig} --file kglobalshortcutsrc --group "org.kde.spectacle.desktop" --key "WindowUnderCursorScreenShot" \
              "${mkKsc (if cfg.shortcuts.spectacle.windowUnderCursor == null then "none" else cfg.shortcuts.spectacle.windowUnderCursor)
                      (if cfg.shortcuts.spectacle.windowUnderCursor == null then "none" else cfg.shortcuts.spectacle.windowUnderCursor)
                      "Capture Window Under Cursor"}"

            ${kwriteconfig} --file kglobalshortcutsrc --group "org.kde.spectacle.desktop" --key "LaunchWithoutTakingScreenshot" \
              "${mkKsc (if cfg.shortcuts.spectacle.launchWithoutScreenshot == null then "none" else cfg.shortcuts.spectacle.launchWithoutScreenshot)
                      (if cfg.shortcuts.spectacle.launchWithoutScreenshot == null then "none" else cfg.shortcuts.spectacle.launchWithoutScreenshot)
                      "Launch without taking a screenshot"}"

            ${kwriteconfig} --file kglobalshortcutsrc --group "org.kde.spectacle.desktop" --key "Launch" \
              "${mkKsc (if cfg.shortcuts.spectacle.launch == null then "none" else cfg.shortcuts.spectacle.launch)
                      (if cfg.shortcuts.spectacle.launch == null then "none" else cfg.shortcuts.spectacle.launch)
                      "Launch"}"

            ${kwriteconfig} --file kglobalshortcutsrc --group "org.kde.spectacle.desktop" --key "StartStopRegionRecording" \
              "${mkKsc cfg.shortcuts.spectacle.startStopRegionRecording cfg.shortcuts.spectacle.startStopRegionRecording "Start/Stop Region Recording"}"

            ${kwriteconfig} --file kglobalshortcutsrc --group "org.kde.spectacle.desktop" --key "StartStopScreenRecording" \
              "${mkKsc (lib.concatStringsSep "\t" cfg.shortcuts.spectacle.startStopScreenRecording)
                      (lib.concatStringsSep "\t" cfg.shortcuts.spectacle.startStopScreenRecording)
                      "Start/Stop Screen Recording"}"

            ${kwriteconfig} --file kglobalshortcutsrc --group "org.kde.spectacle.desktop" --key "StartStopWindowRecording" \
              "${mkKsc cfg.shortcuts.spectacle.startStopWindowRecording cfg.shortcuts.spectacle.startStopWindowRecording "Start/Stop Window Recording"}"
          ''}

          # ---- Yakuake ----
          ${lib.optionalString cfg.shortcuts.yakuake.enable ''
            ${kwriteconfig} --file kglobalshortcutsrc --group "yakuake" --key "_k_friendly_name" "Yakuake"
            ${kwriteconfig} --file kglobalshortcutsrc --group "yakuake" --key "toggle-window-state" \
              "${mkKsc cfg.shortcuts.yakuake.toggle cfg.shortcuts.yakuake.toggle "Open/Retract Yakuake"}"
          ''}
        ''}

        ${lib.optionalString cfg.yakuake.configureWindow ''
          # ---- Yakuake settings ----
          ${kwriteconfig} --file yakuakerc --group Window --key Height ${toString cfg.yakuake.height}
          ${kwriteconfig} --file yakuakerc --group Window --key Width ${toString cfg.yakuake.width}
          ${kwriteconfig} --file yakuakerc --group Window --key X ${toString cfg.yakuake.x}
        ''}



        ${lib.optionalString cfg.restartKglobalAccel ''
          # Apply shortcut changes (service names vary slightly across Plasma setups).
          systemctl --user try-restart plasma-kglobalaccel.service kglobalaccel.service kglobalacceld.service >/dev/null 2>&1 || true
        ''}
      '';
  };
}
