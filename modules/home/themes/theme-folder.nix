{ lib, config, ... }:

let
  cfg = config.my.home.themes.themeFolder;

  # Home Manager doesn't provide a "read directory and map it dynamically" helper
  # at eval time, so this module is intentionally explicit: you tell it which
  # subfolders/files from your theme folder should be mapped into XDG config.
  #
  # This is designed to work both with:
  # - local paths (e.g. ./themes/{theme})
  # - flake inputs with `flake = false` (e.g. inputs.hyprlands)
  #
  # You typically point `source` at the root of a theme folder.
  mkSourcePath = subpath: cfg.source + "/${subpath}";

  # Helper for creating an XDG config file mapping.
  #
  # Example:
  #   (mkXdgFile "waybar/config.jsonc" "waybar/config.jsonc")
  #
  # means:
  #   ~/.config/waybar/config.jsonc -> <theme>/waybar/config.jsonc
  mkXdgFile = targetRelPath: sourceRelPath: {
    name = targetRelPath;
    value = {
      source = mkSourcePath sourceRelPath;
    };
  };

  # Helper for creating an XDG config directory mapping.
  #
  # Example:
  #   (mkXdgDir "hypr" "hypr")
  #
  # means:
  #   ~/.config/hypr -> <theme>/hypr (recursively)
  mkXdgDir = targetRelDir: sourceRelDir: {
    name = targetRelDir;
    value = {
      source = mkSourcePath sourceRelDir;
      recursive = true;
    };
  };

  # Convert attrset like { "hypr" = "hypr"; "waybar" = "waybar"; }
  # into an attrset suitable for `xdg.configFile = { ... }`.
  xdgDirLinks = builtins.listToAttrs (lib.mapAttrsToList mkXdgDir cfg.linkDirs);

  # Convert attrset like { "waybar/style.css" = "waybar/style.css"; }
  # into an attrset suitable for `xdg.configFile = { ... }`.
  xdgFileLinks = builtins.listToAttrs (lib.mapAttrsToList mkXdgFile cfg.linkFiles);

  # Optional sanity check helper: prevents easy footguns like empty source.
  sourceIsValid =
    cfg.source != null
    && (builtins.typeOf cfg.source == "path" || builtins.typeOf cfg.source == "string")
    && (toString cfg.source != "");
in
{
  options.my.home.themes.themeFolder = {
    enable = lib.mkEnableOption "Apply a theme folder by linking its contents into ~/.config via XDG";

    # The root folder for the theme.
    #
    # Intended usage:
    #   source = inputs.hyprlands;                      # if repo structure matches
    #   source = inputs.hyprlands + "/themes/{theme}";  # recommended theme subfolder layout
    #   source = ./themes/{theme};
    source = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.oneOf [
          lib.types.path
          lib.types.str
        ]
      );
      default = null;
      description = ''
        Root of the theme folder to apply.

        The module does not automatically scan directories; instead you specify
        what to link via `linkDirs` and `linkFiles`.

        This can be a local path (recommended) or a string path. If you use a
        flake input, the input must be `flake = false` so it is a raw source tree.
      '';
      example = lib.literalExpression "./themes/cobalt";
    };

    # Directory mappings under ~/.config.
    #
    # Each attribute maps:
    #   "<target under ~/.config>" = "<relative path under theme source>";
    #
    # Example:
    #   linkDirs = { "hypr" = "hypr"; "waybar" = "waybar"; };
    linkDirs = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Directories to link into `~/.config`.

        Keys are target directories relative to `~/.config`.
        Values are source directories relative to `source`.

        All linked directories are recursive.
      '';
      example = lib.literalExpression ''
        {
          "hypr" = "hypr";
          "waybar" = "waybar";
          "kitty" = "kitty";
        }
      '';
    };

    # File mappings under ~/.config.
    #
    # Each attribute maps:
    #   "<target under ~/.config>" = "<relative path under theme source>";
    #
    # Example:
    #   linkFiles = {
    #     "gtk-3.0/settings.ini" = "gtk-3.0/settings.ini";
    #   };
    linkFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Individual files to link into `~/.config`.

        Keys are target file paths relative to `~/.config`.
        Values are source file paths relative to `source`.

        Prefer `linkDirs` for whole-app configs; use this when you want only a
        subset of files from a folder.
      '';
      example = lib.literalExpression ''
        {
          "waybar/config.jsonc" = "waybar/config.jsonc";
          "waybar/style.css" = "waybar/style.css";
        }
      '';
    };

    # Optional "do nothing unless enabled and a source is provided" guard.
    # If you want stricter behavior, set this to true.
    requireSource = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to require `source` to be set when enabling the module.

        When true, enabling without a valid `source` will raise an evaluation error.
        When false, enabling with `source = null` becomes a no-op.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.requireSource && !sourceIsValid) {
        assertions = [
          {
            assertion = false;
            message = "my.home.themes.themeFolder.enable is true, but my.home.themes.themeFolder.source is not set (or is empty).";
          }
        ];
      })

      (lib.mkIf (!cfg.requireSource || sourceIsValid) {
        # Merge directory + file links into a single XDG config mapping.
        xdg.configFile = lib.mkMerge [
          xdgDirLinks
          xdgFileLinks
        ];
      })
    ]
  );
}
