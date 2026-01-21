{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.my.home.fonts;

  # Default external font directory for user-scoped Fontconfig.
  #
  # IMPORTANT:
  # - This is only referenced if `enableExternalDir = true`.
  # - This directory is NOT created or mounted by this module.
  defaultExternalDir = "/mnt/Storage/Fonts";

  mkFontconfigLocalConf = dir: ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <dir>${dir}</dir>
    </fontconfig>
  '';
in
{
  options.my.home.fonts = {
    enable = lib.mkEnableOption "User-scoped fonts + Fontconfig (Home Manager)";

    # Keep the default set small to avoid expensive cache work and large downloads.
    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        # Solid baseline fonts (Latin) and sane defaults.
        dejavu_fonts

        # Commonly expected metric-compatible fonts.
        liberation_ttf
        freefont_ttf

        # Emoji support.
        noto-fonts-color-emoji
      ];
      description = ''
        User-scoped font packages.

        These fonts will be installed into your Home Manager profile and made
        available to Fontconfig for your user session.
      '';
    };

    # Installing "all Nerdfonts" is huge, so keep it opt-in.
    #
    # This uses the Nixpkgs `nerd-fonts` meta-package set.
    # If you later want to restrict this, we can switch to selecting specific fonts.
    enableAllNerdFonts = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to install the full Nerd Fonts collection into your user profile.

        NOTE: This is very large and will increase download size and font cache work.
      '';
    };

    # Optional external fonts directory (user-scoped).
    enableExternalDir = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to add an external font directory to your *user* Fontconfig search path.

        Use this if you keep fonts on an external drive and want them discoverable
        for your user session without baking them into the Nix store.
      '';
    };

    externalDir = lib.mkOption {
      type = lib.types.str;
      default = defaultExternalDir;
      example = "/mnt/Zeal/Resources/Fonts";
      description = "Absolute path to an external fonts directory to include in user Fontconfig.";
    };

    # Default family preference (user-level Fontconfig rules).
    defaultMonospace = lib.mkOption {
      type = lib.types.str;
      default = "DejaVu Sans Mono";
      description = "Preferred monospace font family name for user-level Fontconfig.";
    };

    defaultSans = lib.mkOption {
      type = lib.types.str;
      default = "DejaVu Sans";
      description = "Preferred sans-serif font family name for user-level Fontconfig.";
    };

    defaultSerif = lib.mkOption {
      type = lib.types.str;
      default = "DejaVu Serif";
      description = "Preferred serif font family name for user-level Fontconfig.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install fonts in the user profile (avoids system-wide font cache work at boot).
    home.packages =
      cfg.packages
      ++ lib.optionals cfg.enableAllNerdFonts [
        pkgs.nerd-fonts
      ];

    # Enable and manage user Fontconfig.
    #
    # This writes Fontconfig config under ~/.config/fontconfig and will ensure
    # font discovery works for your user session.
    fonts.fontconfig = {
      enable = true;

      # Prefer your chosen defaults.
      defaultFonts = {
        monospace = [
          cfg.defaultMonospace
          "DejaVu Sans Mono"
        ];
        sansSerif = [
          cfg.defaultSans
          "DejaVu Sans"
        ];
        serif = [
          cfg.defaultSerif
          "DejaVu Serif"
        ];
      };
    };

    # Optionally add external dir via a user-local fontconfig snippet.
    #
    # Home Manager doesn't expose every possible fontconfig knob on all versions,
    # so we drop an explicit config snippet in the standard location.
    xdg.configFile."fontconfig/conf.d/99-external-fonts.conf" = lib.mkIf cfg.enableExternalDir {
      text = mkFontconfigLocalConf cfg.externalDir;
    };
  };
}
