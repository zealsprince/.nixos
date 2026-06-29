{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.home.depot;

  # Runtime tools the Linux branch of the script calls by name. On macOS the
  # script references system tools by absolute path, so this stays empty there.
  linuxDeps = with pkgs; [
    curl
    grim # full-screen / region capture (Wayland)
    slurp # interactive region select (Wayland)
    wl-clipboard # wl-copy / wl-paste
    libnotify # notify-send
    coreutils # stat, mktemp
  ];

  # The upload script is kept as a standalone file so it stays readable (and
  # testable) outside Nix. On Linux the script runs from a Plasma global shortcut
  # with a minimal PATH, so prepend the tool paths; on macOS it calls system
  # tools by absolute path and needs nothing.
  depotUpload = pkgs.writeShellScriptBin "depot-upload" (
    lib.optionalString pkgs.stdenv.isLinux ''
      export PATH=${lib.makeBinPath linuxDeps}:''${PATH}
    ''
    + builtins.readFile ./scripts/depot-upload.sh
  );
  exe = "${depotUpload}/bin/depot-upload";

  keyPath = config.age.secrets."depot-api-key".path;

  kwriteconfig = "${pkgs.kdePackages.kconfig}/bin/kwriteconfig6";

  # Plasma binds a global shortcut to an app by its desktop-file id. Each action
  # gets a hidden launcher in ~/.local/share/applications; the activation block
  # below attaches the shortcut to it via kglobalshortcutsrc.
  mkDepotDesktop =
    { name, arg }:
    ''
      [Desktop Entry]
      Type=Application
      Name=${name}
      Exec=env DEPOT_URL=${cfg.url} DEPOT_KEY_FILE=${keyPath} ${exe} ${arg}
      Terminal=false
      NoDisplay=true
      StartupNotify=false
    '';
in
{
  options.my.home.depot = {
    enable = lib.mkEnableOption "Hivecom depot upload script";

    url = lib.mkOption {
      type = lib.types.str;
      default = "https://depot.hivecom.net";
      description = "Depot gateway base URL.";
    };

    secretFile = lib.mkOption {
      type = lib.types.path;
      default = ../../secrets/depot-api-key.age;
      description = "agenix-encrypted file holding the depot API key (depot_...).";
    };

    keybinds = {
      enable = lib.mkEnableOption "global keybinds for depot upload (skhd on macOS, Plasma global shortcuts on Linux)";

      modifiers = lib.mkOption {
        type = lib.types.str;
        default = "cmd + alt + shift";
        description = "skhd modifier chord prefixed onto the depot keybinds (macOS only).";
      };

      # Plasma global shortcuts (Linux). KDE accelerator syntax. These mirror the
      # macOS chord (Cmd+Alt+Shift+3/4/6) with Ctrl standing in for Cmd.
      plasma = {
        shotFull = lib.mkOption {
          type = lib.types.str;
          default = "Ctrl+Alt+Shift+3";
          description = "Plasma shortcut for a full-screen capture and upload.";
        };
        shotRegion = lib.mkOption {
          type = lib.types.str;
          default = "Ctrl+Alt+Shift+4";
          description = "Plasma shortcut for an interactive region capture and upload.";
        };
        clipboard = lib.mkOption {
          type = lib.types.str;
          default = "Ctrl+Alt+Shift+6";
          description = "Plasma shortcut to upload the current clipboard contents.";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets."depot-api-key".file = cfg.secretFile;

    home.packages = [ depotUpload ];

    # macOS hotkeys via skhd (a launchd user agent). The Linux WM binds
    # (Plasma/Hyprland) are handled separately, so this stays darwin-only.
    #
    # Key codes used instead of digits so the Shift modifier doesn't turn
    # "3" into "#" and break the match: 0x14=3, 0x15=4, 0x16=6 (0x17=5, video, later).
    services.skhd = lib.mkIf (cfg.keybinds.enable && pkgs.stdenv.isDarwin) {
      enable = true;
      config = ''
        # Hivecom depot upload (resulting URL lands on the clipboard)
        ${cfg.keybinds.modifiers} - 0x14 : DEPOT_URL=${cfg.url} DEPOT_KEY_FILE=${keyPath} ${exe} shot-full
        ${cfg.keybinds.modifiers} - 0x15 : DEPOT_URL=${cfg.url} DEPOT_KEY_FILE=${keyPath} ${exe} shot-region
        ${cfg.keybinds.modifiers} - 0x16 : DEPOT_URL=${cfg.url} DEPOT_KEY_FILE=${keyPath} ${exe} clipboard
      '';
    };

    # Linux/Plasma hotkeys. KDE binds a global shortcut to an app by its
    # desktop-file id, so each action ships as a hidden launcher and the
    # activation block below attaches the shortcut via kglobalshortcutsrc
    # (same mechanism wm/plasma6.nix uses for Spectacle/Yakuake).
    home.file = lib.mkIf (cfg.keybinds.enable && pkgs.stdenv.isLinux) {
      ".local/share/applications/hivecom-depot-shot-full.desktop".text = mkDepotDesktop {
        name = "Depot: full screenshot";
        arg = "shot-full";
      };
      ".local/share/applications/hivecom-depot-shot-region.desktop".text = mkDepotDesktop {
        name = "Depot: region screenshot";
        arg = "shot-region";
      };
      ".local/share/applications/hivecom-depot-clipboard.desktop".text = mkDepotDesktop {
        name = "Depot: upload clipboard";
        arg = "clipboard";
      };
    };

    home.activation.configureDepotShortcuts =
      lib.mkIf (cfg.keybinds.enable && pkgs.stdenv.isLinux)
        (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          set -e

          ${kwriteconfig} --file kglobalshortcutsrc --group "hivecom-depot-shot-full.desktop" \
            --key "_launch" "${cfg.keybinds.plasma.shotFull},none,Depot: full screenshot"
          ${kwriteconfig} --file kglobalshortcutsrc --group "hivecom-depot-shot-region.desktop" \
            --key "_launch" "${cfg.keybinds.plasma.shotRegion},none,Depot: region screenshot"
          ${kwriteconfig} --file kglobalshortcutsrc --group "hivecom-depot-clipboard.desktop" \
            --key "_launch" "${cfg.keybinds.plasma.clipboard},none,Depot: upload clipboard"

          # Index the new desktop files so the shortcuts can attach, then apply.
          ${pkgs.kdePackages.kservice}/bin/kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
          systemctl --user try-restart plasma-kglobalaccel.service kglobalaccel.service kglobalacceld.service >/dev/null 2>&1 || true
        '');
  };
}
