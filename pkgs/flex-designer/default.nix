{ lib
, appimageTools
, fetchurl
, makeDesktopItem
}:

let
  pname = "flex-designer";
  version = "2.1.0";

  # AppImage asset from:
  # https://github.com/ENIAC-Tech/FlexDesigner/releases/tag/v2.0.9
  #
  # NOTE: Replace sha256 with the correct hash for the AppImage.
  src = fetchurl {
    url = "https://github.com/ENIAC-Tech/FlexDesigner/releases/download/${version}/flex-designer-${version}.x86_64.AppImage";
    sha256 = "sha256-Ms1vpw/C0gmxgRNyxEq/3qjuPiH6k7OJOTyPXSvG4jY=";
  };

  desktopItem = makeDesktopItem {
    name = "FlexDesigner";
    desktopName = "FlexDesigner";
    comment = "Flex Designer";
    exec = "flex-designer %U";
    terminal = false;
    categories = [ "Development" ];
  };

in
appimageTools.wrapType2 {
  inherit pname version src;

  extraPkgs = pkgs: with pkgs; [
    xdotool
    vips
    (python3.withPackages (ps: [ ps.pyaudio ]))
    portaudio
    lm_sensors
    rocmPackages.rocm-smi
    pciutils
  ];

  profile = ''
    export FONTCONFIG_FILE=/etc/fonts/fonts.conf
  '';

  # Try to pick up icons from the AppImage if present; otherwise we still install
  # a workable .desktop file via `desktopItem`.
  extraInstallCommands =
    let
      extracted = appimageTools.extractType2 { inherit pname version src; };
    in
    ''
      # Desktop entry
      install -Dm444 ${desktopItem}/share/applications/*.desktop \
        $out/share/applications/${pname}.desktop

      # Optional icon(s) if they exist in the AppImage
      if [ -d "${extracted}/usr/share/icons" ]; then
        mkdir -p $out/share
        cp -r "${extracted}/usr/share/icons" "$out/share/"
      fi

      # Optional pixmap icon fallback if present
      if [ -d "${extracted}/usr/share/pixmaps" ]; then
        mkdir -p $out/share
        cp -r "${extracted}/usr/share/pixmaps" "$out/share/"
      fi
    '';

  meta = {
    description = "Flex Designer (AppImage)";
    homepage = "https://github.com/ENIAC-Tech/FlexDesigner";
    # Upstream does not clearly specify the license in the release assets.
    license = lib.licenses.unfreeRedistributable or lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "flex-designer";
  };
}
