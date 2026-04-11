{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.my.home.fonts;
in
{
  options.my.home.fonts = {
    enable = lib.mkEnableOption "User-scoped font packages (Home Manager)";

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        dejavu_fonts
        liberation_ttf
        freefont_ttf
        noto-fonts-color-emoji
      ];
      description = ''
        Font packages to install into the user profile.

        Fontconfig is intentionally not managed here — let the WM (e.g. Plasma)
        handle font preferences. These packages just make the fonts available.
      '';
    };

    enableAllNerdFonts = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to install the full Nerd Fonts collection.
        Very large — keep opt-in.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      cfg.packages
      ++ lib.optionals cfg.enableAllNerdFonts [
        pkgs.nerd-fonts
      ];
  };
}
