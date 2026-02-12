{
  appimageTools,
  fetchurl,
  makeDesktopItem,
}:

let
  pname = "spotiflac";
  version = "7.0.9";

  src = fetchurl {
    url = "https://github.com/afkarxyz/SpotiFLAC/releases/download/v7.0.9/SpotiFLAC.AppImage";
    sha256 = "1zrc5i5vm09vszs5vm5p56vr6kc3mbz7yl8x0l299dm6gzrv91fq";
  };

  appimageContents = appimageTools.extract { inherit pname version src; };

  desktopItem = makeDesktopItem {
    name = "spotiflac";
    desktopName = "SpotiFLAC";
    exec = "spotiflac";
    icon = "spotiflac";
    comment = "Download Spotify songs in FLAC quality";
    categories = [
      "Audio"
      "AudioVideo"
      "Network"
    ];
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraPkgs =
    pkgs: with pkgs; [
      webkitgtk_4_1
    ];

  extraInstallCommands = ''
    install -Dm444 ${desktopItem}/share/applications/spotiflac.desktop $out/share/applications/spotiflac.desktop
    install -Dm444 ${appimageContents}/*.png $out/share/icons/hicolor/512x512/apps/spotiflac.png
  '';

  meta = {
    description = "Download Spotify songs in FLAC quality using Deezer";
    homepage = "https://github.com/afkarxyz/SpotiFLAC";
    platforms = [ "x86_64-linux" ];
    mainProgram = "spotiflac";
  };
}
