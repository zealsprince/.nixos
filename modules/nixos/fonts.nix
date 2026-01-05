{ config, pkgs, lib, ... }:

let
  cfg = config.my.fonts;

  # Default external font directory (intended to be a user-managed path that can
  # live on an external drive and be bind-mounted/symlinked as desired).
  #
  # This is *not* created automatically; it is only referenced by fontconfig if enabled.
  defaultExternalDir = "/mnt/Storage/Fonts";

  # Conservative Nerd Fonts selection: "all Nerdfonts" as a single package can be
  # extremely large. If you truly want every patched font, set `my.fonts.nerdFonts = null`
  # and we will install `pkgs.nerd-fonts` or `pkgs.nerdfonts` depending on what
  # exists in your nixpkgs.
  #
  # Note: package naming varies across nixpkgs versions:
  # - older: pkgs.nerdfonts.override { fonts = [ ... ]; }
  # - newer: pkgs.nerd-fonts (attrset of individual fonts)
  nerdFontsPackages =
    if cfg.nerdFonts == null then
      # "All Nerd Fonts" mode.
      #
      # In newer nixpkgs, `pkgs.nerd-fonts` is an attrset that may contain entries
      # that are not installable packages (e.g. helper functors/functions).
      # Filter to derivations only.
      if pkgs ? nerd-fonts then
        let
          vals = lib.attrValues pkgs.nerd-fonts;
        in
        builtins.filter lib.isDerivation vals
      else if pkgs ? nerdfonts then
        # Older nixpkgs: `nerdfonts` is a single derivation containing many fonts.
        [ pkgs.nerdfonts ]
      else
        throw "No Nerd Fonts package found in nixpkgs (expected `pkgs.nerd-fonts` or `pkgs.nerdfonts`)."
    else
      # Selected-fonts mode.
      #
      # Newer nixpkgs uses `pkgs.nerd-fonts` as an attrset of individual font derivations.
      # If specific font names are provided, select them from the attrset.
      if pkgs ? nerd-fonts then
        let
          nf = pkgs.nerd-fonts;
          selected = map (name: nf.${name}) cfg.nerdFonts;
        in
        builtins.filter lib.isDerivation selected
      else if pkgs ? nerdfonts then
        # Older nixpkgs interface (override).
        [ (pkgs.nerdfonts.override { fonts = cfg.nerdFonts; }) ]
      else
        throw "Selected Nerd Fonts requires either `pkgs.nerd-fonts` (attrset) or `pkgs.nerdfonts` (override interface) in this nixpkgs.";
in
{
  options.my.fonts = {
    enable = lib.mkEnableOption "Desktop font configuration (Fontconfig + Nerd Fonts + optional external font directory)";

    # Nerd Fonts:
    # - null => install "all Nerdfonts" (very large)
    # - list => install only those named fonts (recommended)
    nerdFonts = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = [
        "FiraCode"
        "JetBrainsMono"
        "Iosevka"
        "Hack"
        "NerdFontsSymbolsOnly"
      ];
      example = [
        "JetBrainsMono"
        "FiraCode"
        "NerdFontsSymbolsOnly"
      ];
      description = ''
        Nerd Fonts to install.

        - If set to a list of font names, this module installs only those Nerd Fonts.
        - If set to null, this module attempts to install *all* Nerd Fonts. This can
          be very large and will increase build/download size significantly.

        Note: The available font names depend on your nixpkgs version.
      '';
    };

    # External fonts:
    enableExternalDir = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to add an external font directory to Fontconfig's search path.

        This is useful if you keep extra fonts on an external drive and want them
        to be discoverable by applications without copying them into Nix store.

        This module does not manage mounting; ensure the directory is available
        at login/session start.
      '';
    };

    externalDir = lib.mkOption {
      type = lib.types.str;
      default = defaultExternalDir;
      example = "/mnt/Strike/Fonts";
      description = "Absolute path to an external fonts directory to include in Fontconfig.";
    };

    # Default fonts:
    # These are safe defaults; adjust to taste.
    defaultMonospace = lib.mkOption {
      type = lib.types.str;
      default = "JetBrainsMono Nerd Font";
      description = "Default monospace font family name for Fontconfig.";
    };

    defaultSans = lib.mkOption {
      type = lib.types.str;
      default = "Noto Sans";
      description = "Default sans-serif font family name for Fontconfig.";
    };

    defaultSerif = lib.mkOption {
      type = lib.types.str;
      default = "Noto Serif";
      description = "Default serif font family name for Fontconfig.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install fonts system-wide.
    fonts = {
      enableDefaultPackages = true;
      fontDir.enable = true;

      packages = with pkgs; [
        # High-quality baseline fonts
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
        liberation_ttf
        dejavu_fonts
      ] ++ nerdFontsPackages;

      # Fontconfig configuration
      fontconfig = {
        enable = true;

        # Let fontconfig discover user fonts under ~/.local/share/fonts by default
        # (this is standard behavior, included here for clarity).
        # Additionally include an external fonts dir if requested.
        localConf = lib.mkIf cfg.enableExternalDir ''
          <?xml version="1.0"?>
          <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
          <fontconfig>
            <dir>${cfg.externalDir}</dir>
          </fontconfig>
        '';

        defaultFonts = {
          monospace = [ cfg.defaultMonospace "Nerd Fonts Symbols Only" "DejaVu Sans Mono" ];
          sansSerif = [ cfg.defaultSans "Noto Sans" "DejaVu Sans" ];
          serif = [ cfg.defaultSerif "Noto Serif" "DejaVu Serif" ];
        };
      };
    };

    # Helpful note: if external fonts are on removable media, fontconfig caches
    # may become stale; users can run:
    #   fc-cache -rv
    # after mounting or updating the directory.
  };
}
