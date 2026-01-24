{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.my.home.wm.hyprland;
in
{
  options.my.home.wm.hyprland = {
    enable = lib.mkEnableOption "Hyprland (Home Manager) with theme-folder consumption";

    # You can point this at:
    # - a local theme folder: ./themes/{theme}
    # - a flake input with flake=false: inputs.hyprlands + "/themes/{theme}"
    theme = {
      enable = lib.mkEnableOption "Apply a theme folder into ~/.config (hypr/waybar/gtk/etc)";

      source = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.oneOf [
            lib.types.path
            lib.types.str
          ]
        );
        default = null;
        description = ''
          Root path of the theme folder.

          This module does not auto-scan directories. You choose what to link via
          `consume` and `extraLinkDirs/extraLinkFiles` below.
        '';
        example = lib.literalExpression "./themes/{theme}";
      };

      # Development mode: use out-of-store symlinks for live iteration.
      dev = {
        enable = lib.mkEnableOption "Use out-of-store symlinks (requires --impure)";
      };

      # Theme namespace wiring:
      #
      # This creates:
      #   ~/.config/hyprlands/active -> <theme folder>
      #
      # This is the "selected theme" pointer for humans/scripts. However, we do
      # NOT use `~/.config/hyprlands/active/...` as a *source* for other links,
      # because that path is a runtime user path and may not exist during Nix eval.
      #
      # Instead, app config entrypoints are linked directly from `theme.source/<app>`.
      namespace = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Create ~/.config/hyprlands/active symlink and export HYPR_THEME_* namespace env vars.";
        };

        activeSymlink = lib.mkOption {
          type = lib.types.str;
          default = "${config.xdg.configHome}/hyprlands/active";
          description = "Path to the 'active theme' symlink (default: ~/.config/hyprlands/active).";
        };

        sharedDirName = lib.mkOption {
          type = lib.types.str;
          default = "hyprlands";
          description = "Name of the shared directory inside a theme (default: hyprlands).";
        };
      };

      # Which parts of the theme folder to expose into canonical XDG config locations.
      #
      # These are linked directly from:
      #   <theme.source>/<app>
      #
      # The "active theme" pointer still exists, but remains a pointer only.
      consume = {
        hypr = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Link `<theme>/hypr` into `~/.config/hypr`.";
        };

        waybar = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Link `<theme>/waybar` into `~/.config/waybar`.";
        };

        kitty = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Link `<theme>/kitty` into `~/.config/kitty`.";
        };

        fastfetch = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Link `<theme>/fastfetch` into `~/.config/fastfetch`.";
        };

        rofi = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Link `<theme>/rofi` into `~/.config/rofi`.";
        };

        waypaper = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Link `<theme>/waypaper` into `~/.config/waypaper`.";
        };

        gtk3 = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Link `<theme>/gtk-3.0` into `~/.config/gtk-3.0`.";
        };

        gtk4 = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Link `<theme>/gtk-4.0` into `~/.config/gtk-4.0`.";
        };
      };

      # Extra directory mappings (also linked from theme.source).
      #
      # Keys are targets under `~/.config`. Values are relative paths under the theme folder.
      extraLinkDirs = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Extra theme directory links.
          Keys are targets under `~/.config`. Values are paths relative to the theme `source`.
        '';
      };

      # Extra file mappings (linked from theme.source).
      #
      # Keys are targets under `~/.config`. Values are relative paths under the theme folder.
      extraLinkFiles = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Extra theme file links.
          Keys are targets under `~/.config`. Values are paths relative to the theme `source`.
        '';
      };
    };

    # Minimal, opinionated packages you almost certainly want with Hyprland configs.
    # Keep this small; you likely already manage packages elsewhere.
    packages = {
      enable = lib.mkEnableOption "Install a small set of Hyprland-adjacent user packages";
      extra = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Extra packages to install when `packages.enable = true`.";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    let
      consume = cfg.theme.consume;
      dev = cfg.theme.dev.enable;

      activeSymlink = cfg.theme.namespace.activeSymlink;
      sharedDirName = cfg.theme.namespace.sharedDirName;

      # Capture raw path string for dev mode to ensure no store copying happens
      devSourcePath = toString cfg.theme.source;

      # Helper: choose between standard source (store path) and out-of-store symlink (dev mode).
      #
      # - Standard (dev=false): `source = /nix/store/...` (copied in)
      # - Dev (dev=true): `source = config.lib.file.mkOutOfStoreSymlink /absolute/path`
      mkLink =
        subpath:
        if dev then
          config.lib.file.mkOutOfStoreSymlink (devSourcePath + "/${subpath}")
        else
          cfg.theme.source + "/${subpath}";

      # Helper for directory links.
      #
      # Note: `mkOutOfStoreSymlink` creates a symlink to the directory itself.
      # Standard `source` on a directory (without `recursive=true`) creates a symlink to the store path of that directory.
      #
      # We intentionally avoid `recursive=true` here so that the directory itself is the link target.
      mkDirLink = subpath: {
        source = mkLink subpath;
        recursive = if dev then false else true;
        force = true;
      };

      # Build an attrset of xdg.configFile directory links.
      dirLinks =
        lib.optionalAttrs consume.hypr { "hypr" = mkDirLink "hypr"; }
        // lib.optionalAttrs consume.waybar { "waybar" = mkDirLink "waybar"; }
        // lib.optionalAttrs consume.kitty { "kitty" = mkDirLink "kitty"; }
        // lib.optionalAttrs consume.fastfetch { "fastfetch" = mkDirLink "fastfetch"; }
        // lib.optionalAttrs consume.rofi { "rofi" = mkDirLink "rofi"; }
        // lib.optionalAttrs (consume.waypaper && dev) { "waypaper" = mkDirLink "waypaper"; }
        // lib.optionalAttrs consume.gtk3 { "gtk-3.0" = mkDirLink "gtk-3.0"; }
        // lib.optionalAttrs consume.gtk4 { "gtk-4.0" = mkDirLink "gtk-4.0"; };

      # Apply extraLinkDirs.
      extraDirLinks = lib.mapAttrs (_target: rel: {
        source = mkLink rel;
        recursive = if dev then false else true;
        force = true;
      }) cfg.theme.extraLinkDirs;

      # Apply extraLinkFiles.
      extraFileLinks = lib.mapAttrs (_target: rel: {
        source = mkLink rel;
        force = true;
      }) cfg.theme.extraLinkFiles;

      # Links to generate.
      allLinks =
        (lib.optionalAttrs cfg.theme.namespace.enable {
          "hyprlands/active" = {
            source = if dev then config.lib.file.mkOutOfStoreSymlink devSourcePath else cfg.theme.source;
            force = true;
          };
          "hyprlands/current" = {
            source = if dev then config.lib.file.mkOutOfStoreSymlink devSourcePath else cfg.theme.source;
            force = true;
          };
        })
        // dirLinks
        // extraDirLinks
        // extraFileLinks;
    in
    {
      assertions = [
        {
          assertion = (!cfg.theme.enable) || (cfg.theme.source != null && toString cfg.theme.source != "");
          message = "my.home.wm.hyprland.theme.enable is true, but my.home.wm.hyprland.theme.source is not set.";
        }
      ];

      # xdg.configFile (standard mode):
      xdg.configFile = lib.mkIf (cfg.theme.enable && !dev) allLinks;

      # Cleanup script (standard mode):
      # When switching from dev (symlinks) to standard (store paths), we must remove
      # the directory symlinks so Home Manager can create real directories and populate them.
      home.activation.cleanupHyprlandThemeDev = lib.mkIf (cfg.theme.enable && !dev) (
        lib.hm.dag.entryBefore [ "checkLinkTargets" ] (
          let
            # Targets that are directories in standard mode (recursive=true)
            # but were likely symlinks in dev mode.
            dirsToClean =
              lib.optionalAttrs consume.hypr { "hypr" = true; }
              // lib.optionalAttrs consume.waybar { "waybar" = true; }
              // lib.optionalAttrs consume.kitty { "kitty" = true; }
              // lib.optionalAttrs consume.fastfetch { "fastfetch" = true; }
              // lib.optionalAttrs consume.rofi { "rofi" = true; }
              // lib.optionalAttrs consume.waypaper { "waypaper" = true; }
              // lib.optionalAttrs consume.gtk3 { "gtk-3.0" = true; }
              // lib.optionalAttrs consume.gtk4 { "gtk-4.0" = true; }
              // cfg.theme.extraLinkDirs
              // (lib.optionalAttrs cfg.theme.namespace.enable {
                "hyprlands/active" = true;
                "hyprlands/current" = true;
              });

            commands = lib.mapAttrsToList (target: _: ''
              targetPath="${config.xdg.configHome}/${target}"
              if [ -L "$targetPath" ]; then
                echo "Cleaning up dev-mode symlink: $targetPath"
                $DRY_RUN_CMD rm "$targetPath"
              fi
            '') dirsToClean;
          in
          builtins.concatStringsSep "\n" commands
        )
      );

      # Mutable Configs (Standard Mode):
      # Some apps (Waypaper) need to write to their config files.
      # We copy them from the theme instead of symlinking.
      home.activation.setupMutableHyprlandConfigs = lib.mkIf (cfg.theme.enable && !dev) (
        lib.hm.dag.entryAfter [ "linkGeneration" ] (
          let
            sourceDir = "${cfg.theme.source}/waypaper";
            targetDir = "${config.xdg.configHome}/waypaper";
          in
          lib.optionalString consume.waypaper ''
            if [ -d "${sourceDir}" ]; then
              $DRY_RUN_CMD mkdir -p "${targetDir}"
              # Copy files, overwriting existing ones to apply theme, but ensuring write permissions
              $DRY_RUN_CMD cp -Lf --no-preserve=mode,ownership "${sourceDir}/"* "${targetDir}/"
              $DRY_RUN_CMD chmod -R +w "${targetDir}"
            fi
          ''
        )
      );

      # Activation script (dev mode):
      # Directly symlink paths to avoid the Nix store symlink chain.
      home.activation.linkHyprlandThemeDev = lib.mkIf (cfg.theme.enable && dev) (
        lib.hm.dag.entryAfter [ "writeBoundary" ] (
          let
            # Map target (relative to ~/.config) -> source (relative to theme root)
            linkMap =
              lib.optionalAttrs consume.hypr { "hypr" = "hypr"; }
              // lib.optionalAttrs consume.waybar { "waybar" = "waybar"; }
              // lib.optionalAttrs consume.kitty { "kitty" = "kitty"; }
              // lib.optionalAttrs consume.fastfetch { "fastfetch" = "fastfetch"; }
              // lib.optionalAttrs consume.rofi { "rofi" = "rofi"; }
              // lib.optionalAttrs consume.waypaper { "waypaper" = "waypaper"; }
              // lib.optionalAttrs consume.gtk3 { "gtk-3.0" = "gtk-3.0"; }
              // lib.optionalAttrs consume.gtk4 { "gtk-4.0" = "gtk-4.0"; }
              // cfg.theme.extraLinkDirs
              // cfg.theme.extraLinkFiles
              // (lib.optionalAttrs cfg.theme.namespace.enable {
                "hyprlands/active" = ".";
                "hyprlands/current" = ".";
              });

            # Generate the ln -s commands
            commands = lib.mapAttrsToList (target: srcRel: ''
              targetPath="${config.xdg.configHome}/${target}"
              sourcePath="${devSourcePath}/${srcRel}"

              $DRY_RUN_CMD mkdir -p "$(dirname "$targetPath")"

              # If target is an empty directory (leftover from standard mode), remove it so we can symlink
              if [ -d "$targetPath" ] && [ -z "$(ls -A "$targetPath")" ]; then
                echo "Removing empty directory $targetPath to replace with dev symlink"
                $DRY_RUN_CMD rmdir "$targetPath"
              fi

              if [ -e "$targetPath" ] && [ ! -L "$targetPath" ]; then
                echo "WARN: $targetPath exists and is not a symlink. Skipping to protect data."
              else
                # Force link to point to the local source path
                $DRY_RUN_CMD ln -sfn "$sourcePath" "$targetPath"
              fi
            '') linkMap;
          in
          builtins.concatStringsSep "\n" commands
        )
      );

      # Export stable env vars for theme configs (Waybar/Hypr/etc.)
      #
      # If the namespace pointer is disabled, we still export:
      # - HYPR_THEME_HYPRLANDS_DIR as the theme source path
      # - HYPR_THEME_OTHER_DIR     as <theme source>/<sharedDirName>
      home.sessionVariables = lib.mkIf cfg.theme.enable (
        if cfg.theme.namespace.enable then
          {
            HYPR_THEME_HYPRLANDS_DIR = activeSymlink;
            HYPR_THEME_OTHER_DIR = "${activeSymlink}/${sharedDirName}";
          }
        else
          {
            HYPR_THEME_HYPRLANDS_DIR = if dev then devSourcePath else toString cfg.theme.source;
            HYPR_THEME_OTHER_DIR =
              if dev then
                "${devSourcePath}/${sharedDirName}"
              else
                "${toString cfg.theme.source}/${sharedDirName}";
          }
      );

      # Optional package set.
      home.packages = lib.mkIf cfg.packages.enable (
        (with pkgs; [
          # Helpful for many Hyprland setups; safe defaults.
          waybar
          kitty
        ])
        ++ cfg.packages.extra
      );
    }
  );
}
