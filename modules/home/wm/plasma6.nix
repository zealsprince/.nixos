{ config, pkgs, lib, ... }:

let
  cfg = config.my.home.wm.plasma6;

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

  mkKsc = primary: defaultShortcut: description:
    "${primary},${defaultShortcut},${description}";

  # Parse section headers like:
  #   [Application settings for Alacritty]
  # into stable KWin rule IDs. We store:
  #   [General]
  #   count=...
  #   rules=rule1,rule2,...
  # and rewrite each rule section header to [<id>]
  #
  # This makes KWin actually list/manage the rules in the UI.
  ruleIdFromHeader =
    header:
    let
      # strip surrounding [ ]
      inner = lib.removeSuffix "]" (lib.removePrefix "[" header);
      # slugify
      slug =
        lib.toLower
          (builtins.replaceStrings
            [ " " "/" ":" "," "." "(" ")" "[" "]" "{" "}" "'" "\"" ]
            [ "-" "-" "-" "-" "-" ""  ""  ""  ""  ""  ""  ""  "" ]
            inner);
      compact = lib.replaceStrings [ "--" "---" "----" "-----" ] [ "-" "-" "-" "-" ] slug;
    in
      "rule-${compact}";

  generateKwinRulesRc =
    rulesText:
    let
      isHeader = line: lib.hasPrefix "[" line && lib.hasSuffix "]" line;
      lines = lib.splitString "\n" rulesText;

      headers = builtins.filter isHeader lines;
      ids = map ruleIdFromHeader headers;

      # Rewrite headers to ids in order; keep all other lines unchanged.
      rewritten =
        builtins.concatStringsSep "\n"
          (lib.foldl'
            (acc: line:
              if isHeader line then
                let
                  idx = acc.idx;
                  id = builtins.elemAt ids idx;
                in
                  {
                    idx = idx + 1;
                    out = acc.out ++ [ "[${id}]" ];
                  }
              else
                {
                  idx = acc.idx;
                  out = acc.out ++ [ line ];
                })
            { idx = 0; out = [ ]; }
            lines).out;

      general =
        ''
          [General]
          count=${toString (builtins.length ids)}
          rules=${lib.concatStringsSep "," ids}

        '';
    in
      general + rewritten;
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

      dropbox = {
        enable = lib.mkEnableOption "Autostart Dropbox";
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

    kwinRules = {
      enable = lib.mkEnableOption "Manage KWin window rules via ~/.config/kwinrulesrc.";

      rulesFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to a KWin rules file exported from the KWin UI (*.kwinrule) or an ini-like rules file.

          This module will IMPORT it by converting it into a real `kwinrulesrc` (adds `[General]`
          with a rules index and rewrites section headers to stable rule IDs), so the rules
          show up inside System Settings → Window Management → Window Rules.

          Recommended usage: keep a host-specific file under `hosts/<HOST>/.../*.kwinrule`
          and point this option at it.
        '';
      };
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
          mkAutostartDesktop {
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
          mkAutostartDesktop {
            name = "Slack (Hidden)";
            # Some Electron apps ignore "start minimized" flags when launched via autostart unless
            # executed through a shell; also avoid inheriting startup activation from autostart.
            exec = "${pkgs.runtimeShell} -lc '${pkgs.slack}/bin/slack --start-minimized --disable-gpu >/dev/null 2>&1 & disown'";
            startupNotify = false;
          };
      })

      (lib.mkIf (cfg.autostart.enable && cfg.autostart.teams.enable) {
        ".config/autostart/teams.desktop".text =
          mkAutostartDesktop {
            name = "Teams (Hidden)";
            # Teams-for-Linux is Electron-based; enforce hidden startup by launching via a shell.
            exec = "${pkgs.runtimeShell} -lc '${pkgs.teams-for-linux}/bin/teams-for-linux --hidden --disable-gpu >/dev/null 2>&1 & disown'";
            startupNotify = false;
          };
      })

      (lib.mkIf (cfg.autostart.enable && cfg.autostart.dropbox.enable) {
        ".config/autostart/dropbox.desktop".text =
          mkAutostartDesktop {
            name = "Dropbox";
            exec = "${pkgs.dropbox}/bin/dropbox";
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
          mkAutostartDesktop {
            name = "OpenSnitch UI";
            exec = "${pkgs.opensnitch-ui}/bin/opensnitch-ui";
          };
      })

      (lib.mkIf (cfg.autostart.enable && cfg.autostart.qpwgraph.enable) {
        ".config/autostart/qpwgraph.desktop".text =
          mkAutostartDesktop {
            name = "qpwgraph";
            exec = "${pkgs.qpwgraph}/bin/qpwgraph";
          };
      })

      (lib.mkIf (cfg.autostart.enable && cfg.autostart.mullvadVpn.enable) {
        ".config/autostart/mullvad-vpn.desktop".text =
          mkAutostartDesktop {
            name = "Mullvad VPN";
            exec = "${pkgs.mullvad-vpn}/bin/mullvad-vpn";
          };
      })

      (lib.mkIf (cfg.kwinRules.enable && cfg.kwinRules.rulesFile != null) {
        ".config/kwinrulesrc".text =
          generateKwinRulesRc (builtins.readFile cfg.kwinRules.rulesFile);
      })
    ];

    # -------------------------------------------------------------------------
    # Activation: write KDE config + global shortcuts
    # -------------------------------------------------------------------------
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

        ${lib.optionalString (cfg.kwinRules.enable && cfg.kwinRules.rulesFile != null) ''
          # Best-effort: prompt KWin to reload rules by restarting it.
          # Service names vary across setups (Wayland vs X11, packaging differences).
          systemctl --user try-restart plasma-kwin_wayland.service plasma-kwin_x11.service kwin_wayland.service kwin_x11.service >/dev/null 2>&1 || true
        ''}

        ${lib.optionalString cfg.restartKglobalAccel ''
          # Apply shortcut changes (service names vary slightly across Plasma setups).
          systemctl --user try-restart plasma-kglobalaccel.service kglobalaccel.service kglobalacceld.service >/dev/null 2>&1 || true
        ''}
      '';
  };
}
