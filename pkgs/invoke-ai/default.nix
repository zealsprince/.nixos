{ lib
, appimageTools
, fetchurl
, makeDesktopItem
}:

let
  pname = "invoke-ai";
  version = "1.8.1";

  src = fetchurl {
    url = "https://github.com/invoke-ai/launcher/releases/download/v${version}/Invoke-Community-Edition-${version}.AppImage";
    sha256 = "0ix7lfp1n5d9vynpqxqr1z9hfsb9fmi4zn7javkmsbkw144xv782";
  };

  desktopItem = makeDesktopItem {
    name = "InvokeAI";
    desktopName = "InvokeAI";
    comment = "InvokeAI Community Edition Launcher";
    exec = "invoke-ai %U";
    terminal = false;
    categories = [ "Graphics" "Art" "Development" ];
  };

in
appimageTools.wrapType2 {
  inherit pname version src;

  extraPkgs = pkgs: [
    pkgs.zstd
    pkgs.gcc
    pkgs.binutils
    pkgs.rocmPackages.rocminfo
  ];

  extraInstallCommands =
    let
      extracted = appimageTools.extractType2 { inherit pname version src; };
    in
    ''
      install -Dm444 ${desktopItem}/share/applications/*.desktop \
        $out/share/applications/${pname}.desktop

      if [ -d "${extracted}/usr/share/icons" ]; then
        mkdir -p $out/share
        cp -r "${extracted}/usr/share/icons" "$out/share/"
      fi

      if [ -d "${extracted}/usr/share/pixmaps" ]; then
        mkdir -p $out/share
        cp -r "${extracted}/usr/share/pixmaps" "$out/share/"
      fi
    '';

  meta = {
    description = "InvokeAI Launcher (AppImage)";
    homepage = "https://github.com/invoke-ai/launcher";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "invoke-ai";
  };
}
