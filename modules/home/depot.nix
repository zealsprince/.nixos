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
    wl-clipboard # wl-copy / wl-paste (works on KWin and wlroots)
    libnotify # notify-send
    coreutils # stat, mktemp
    # Screenshot backends: Spectacle on KWin/Plasma (grim can't capture there,
    # KWin lacks wlr-screencopy), grim + slurp on wlroots compositors (Hyprland).
    kdePackages.spectacle
    grim
    slurp
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

  # Saved-copy dirs passed to every launcher. Shots read DEPOT_SHOT_DIR,
  # clipboard reads DEPOT_CLIP_DIR; passing both everywhere is harmless since
  # each command only uses the one it cares about. Null = upload-only.
  shotDirEnv = lib.optionalString (cfg.screenshotDir != null) " DEPOT_SHOT_DIR=${cfg.screenshotDir}";
  clipDirEnv = lib.optionalString (cfg.clipboardDir != null) " DEPOT_CLIP_DIR=${cfg.clipboardDir}";

  kwriteconfig = "${pkgs.kdePackages.kconfig}/bin/kwriteconfig6";

  # Plasma binds a global shortcut to an app by its desktop-file id. Each action
  # gets a hidden launcher in ~/.local/share/applications; the activation block
  # below attaches the shortcut to it via kglobalshortcutsrc.
  #
  # The Exec runs through a shell because keyPath is "$XDG_RUNTIME_DIR/agenix/..."
  # (the agenix HM secret lives under the runtime dir). KDE's launcher does not
  # expand env vars in Exec, so a bare `env DEPOT_KEY_FILE=$XDG_RUNTIME_DIR/...`
  # passes the literal string and the key read fails. The shell expands it.
  #
  # X-KDE-GlobalAccel-CommandShortcut=true is what makes KWin grab the physical
  # key. Without it the shortcut registers (shows in settings, fires via dbus
  # invokeShortcut) but the keypress never reaches it. Plasma's own "command"
  # custom shortcuts carry this field.
  #
  # Exec calls `depot-upload` by name, NOT its /nix/store path. kglobalacceld
  # caches the launch command in memory and only re-reads it on restart/login,
  # so a store-path Exec (which changes on every script edit) would silently keep
  # launching the old build until the next relogin. The bare name is stable - it
  # resolves via the session PATH (home.packages is on it) to the current build.
  mkDepotDesktop =
    { name, arg }:
    ''
      [Desktop Entry]
      Type=Application
      Name=${name}
      Exec=${pkgs.runtimeShell} -c 'exec env DEPOT_URL=${cfg.url} DEPOT_KEY_FILE=${keyPath}${shotDirEnv}${clipDirEnv} depot-upload ${arg}'
      Terminal=false
      NoDisplay=true
      StartupNotify=false
      X-KDE-GlobalAccel-CommandShortcut=true
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

    screenshotDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "${config.home.homeDirectory}/Sharing/Screenshots";
      example = "/mnt/Zeal/Andrew/Sharing/Screenshots";
      description = "Directory to also save screenshots (timestamped) before upload. Null = upload-only. Defaults under the home dir; override per host (e.g. a data mount).";
    };

    clipboardDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "${config.home.homeDirectory}/Sharing/Clipboards";
      example = "/mnt/Zeal/Andrew/Sharing/Clipboards";
      description = "Directory to also save clipboard uploads (timestamped) before upload. Null = upload-only. Defaults under the home dir; override per host (e.g. a data mount).";
    };

    keybinds = {
      enable = lib.mkEnableOption "global keybinds for depot upload (skhd on macOS, Plasma global shortcuts on Linux)";

      modifiers = lib.mkOption {
        type = lib.types.str;
        default = "cmd + alt + shift";
        description = "skhd modifier chord prefixed onto the depot keybinds (macOS only).";
      };

      # Plasma global shortcuts (Linux). KDE accelerator syntax. These mirror the
      # macOS chord (Cmd+Alt+Shift+3/4/6) with Ctrl for Cmd, BUT Plasma stores
      # the shifted symbol, not "Shift+<digit>": pressing Ctrl+Alt+Shift+6 emits
      # Ctrl+Alt+^ (Shift is consumed making the symbol), so the bind must read
      # Ctrl+Alt+^ or the key grab never matches. Same trick plasma6.nix uses for
      # Spectacle (Ctrl+Meta+@, Ctrl+Meta+^, ...). Symbols are US-layout: Shift+3
      # =#, Shift+4=$, Shift+6=^.
      plasma = {
        shotFull = lib.mkOption {
          type = lib.types.str;
          default = "Ctrl+Alt+#"; # Ctrl+Alt+Shift+3
          description = "Plasma shortcut for a full-screen capture and upload.";
        };
        shotRegion = lib.mkOption {
          type = lib.types.str;
          default = "Ctrl+Alt+$"; # Ctrl+Alt+Shift+4
          description = "Plasma shortcut for an interactive region capture and upload.";
        };
        clipboard = lib.mkOption {
          type = lib.types.str;
          default = "Ctrl+Alt+^"; # Ctrl+Alt+Shift+6
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
        ${cfg.keybinds.modifiers} - 0x14 : DEPOT_URL=${cfg.url} DEPOT_KEY_FILE=${keyPath}${shotDirEnv}${clipDirEnv} ${exe} shot-full
        ${cfg.keybinds.modifiers} - 0x15 : DEPOT_URL=${cfg.url} DEPOT_KEY_FILE=${keyPath}${shotDirEnv}${clipDirEnv} ${exe} shot-region
        ${cfg.keybinds.modifiers} - 0x16 : DEPOT_URL=${cfg.url} DEPOT_KEY_FILE=${keyPath}${shotDirEnv}${clipDirEnv} ${exe} clipboard
      '';
    };

    # Linux/Plasma hotkeys. KDE binds a global shortcut to an app by its
    # desktop-file id, so each action ships as a hidden launcher and the
    # activation block below attaches the shortcut via kglobalshortcutsrc.
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

          # App launch shortcuts live under the [services] subgroup, the same
          # place Plasma stores app shortcuts like Alacritty. A top-level
          # [<id>.desktop] group registers a component and grabs the key but has
          # no launch handler, so the keypress fires into nothing.
          ${kwriteconfig} --file kglobalshortcutsrc --group services --group "hivecom-depot-shot-full.desktop" \
            --key "_launch" "${cfg.keybinds.plasma.shotFull}"
          ${kwriteconfig} --file kglobalshortcutsrc --group services --group "hivecom-depot-shot-region.desktop" \
            --key "_launch" "${cfg.keybinds.plasma.shotRegion}"
          ${kwriteconfig} --file kglobalshortcutsrc --group services --group "hivecom-depot-clipboard.desktop" \
            --key "_launch" "${cfg.keybinds.plasma.clipboard}"

          # Drop stale top-level entries written by earlier versions of this
          # module; left in place they shadow the [services] ones above.
          ${kwriteconfig} --file kglobalshortcutsrc --group "hivecom-depot-shot-full.desktop" --key "_launch" --delete || true
          ${kwriteconfig} --file kglobalshortcutsrc --group "hivecom-depot-shot-region.desktop" --key "_launch" --delete || true
          ${kwriteconfig} --file kglobalshortcutsrc --group "hivecom-depot-clipboard.desktop" --key "_launch" --delete || true

          # Index the desktop files so the shortcuts can attach, then apply.
          ${pkgs.kdePackages.kservice}/bin/kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
          systemctl --user try-restart plasma-kglobalaccel.service kglobalaccel.service kglobalacceld.service >/dev/null 2>&1 || true
        '');
  };
}
