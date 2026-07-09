{
  appimageTools,
  fetchurl,
  makeDesktopItem,
}:

let
  pname = "spotiflac";
  version = "7.1.9";

  src = fetchurl {
    url = "https://github.com/spotbye/SpotiFLAC/releases/download/v${version}/SpotiFLAC.AppImage";
    sha256 = "0zy6in97ch9z1c2pyzd8cvaqvf74kdds6d41ycpqnmffjpw7i3h6";
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
    homepage = "https://github.com/spotbye/SpotiFLAC";
    platforms = [ "x86_64-linux" ];
    mainProgram = "spotiflac";
  };
}
