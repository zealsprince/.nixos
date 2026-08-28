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

        Font preferences are otherwise left to the WM (e.g. Plasma), so these
        packages just make the fonts available. The CJK fallback below is the
        one thing fontconfig is managed for here.
      '';
    };

    cjkFallback = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Pin Noto Sans CJK ahead of other fonts for Japanese and Chinese text,
        and install it so the rule has something to point at.
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
      ++ lib.optionals cfg.cjkFallback [
        pkgs.noto-fonts-cjk-sans
        pkgs.noto-fonts-cjk-serif
      ]
      ++ lib.optionals cfg.enableAllNerdFonts [
        pkgs.nerd-fonts
      ];

    # Several kana display fonts I have in ~/.local/share/fonts (the GN* set,
    # Mikiyu) map the entire kanji range in their cmap but ship empty outlines
    # for it. Fontconfig scores that as full Japanese coverage, so they win
    # generic fallback and kanji come out as blank space with no tofu to hint
    # at why. Per-character fallback can't save it: the codepoint is present,
    # just blank, so nothing further down the list ever gets asked. Pinning a
    # real CJK face in front for CJK requests is the only fix. Latin is
    # untouched since the rules only fire when the pattern carries the lang.
    xdg.configFile."fontconfig/conf.d/99-cjk-fallback.conf" = lib.mkIf cfg.cjkFallback {
      text = ''
        <?xml version='1.0'?>
        <!DOCTYPE fontconfig SYSTEM 'urn:fontconfig:fonts.dtd'>
        <fontconfig>
          <match target="pattern">
            <test name="lang" compare="contains"><string>ja</string></test>
            <edit name="family" mode="prepend" binding="strong"><string>Noto Sans CJK JP</string></edit>
          </match>
          <match target="pattern">
            <test name="lang" compare="contains"><string>zh-cn</string></test>
            <edit name="family" mode="prepend" binding="strong"><string>Noto Sans CJK SC</string></edit>
          </match>
          <match target="pattern">
            <test name="lang" compare="contains"><string>zh-tw</string></test>
            <edit name="family" mode="prepend" binding="strong"><string>Noto Sans CJK TC</string></edit>
          </match>
          <match target="pattern">
            <test name="lang" compare="contains"><string>ko</string></test>
            <edit name="family" mode="prepend" binding="strong"><string>Noto Sans CJK KR</string></edit>
          </match>
        </fontconfig>
      '';
    };
  };
}
