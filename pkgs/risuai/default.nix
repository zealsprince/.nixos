{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  wrapGAppsHook3,
  makeWrapper,
  # Runtime dependencies
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libappindicator-gtk3,
  libdrm,
  libgbm,
  libnotify,
  libuuid,
  libxcb,
  libxkbcommon,
  mesa,
  nspr,
  nss,
  pango,
  systemd,
  udev,
  webkitgtk_4_1,
  xorg,
  xdg-utils,
  openssl,
  glib-networking,
}:

stdenv.mkDerivation rec {
  pname = "risuai";
  version = "2026.1.90";

  src = fetchurl {
    url = "https://github.com/kwaroran/RisuAI/releases/download/v${version}/RisuAI_${version}_amd64.deb";
    sha256 = "1rav7zpl37jzml60v7633j7jpqcf3mqpsx6alh4gz5kfbxdahvwi";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    wrapGAppsHook3
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libappindicator-gtk3
    libdrm
    libgbm
    libnotify
    libuuid
    libxcb
    libxkbcommon
    mesa
    nspr
    nss
    pango
    systemd
    udev
    webkitgtk_4_1
    xorg.libX11
    xorg.libXScrnSaver
    xorg.libXcomposite
    xorg.libXcursor
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXi
    xorg.libXrandr
    xorg.libXrender
    xorg.libXtst
    xorg.libxcb
    xdg-utils
    openssl
    glib-networking
  ];

  runtimeDependencies = [
    (lib.getLib udev)
    libappindicator-gtk3
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r usr/* $out/

    runHook postInstall
  '';

  preFixup = ''
    # Shim 'open' to 'xdg-open' because the app tries to run 'open'
    mkdir -p $out/libexec/risuai-shims
    cat > $out/libexec/risuai-shims/open <<EOF
    #!/bin/sh
    exec ${xdg-utils}/bin/xdg-open "\$@"
    EOF
    chmod +x $out/libexec/risuai-shims/open

    gappsWrapperArgs+=(--prefix PATH : "$out/libexec/risuai-shims")
  '';

  postFixup = ''
    # The deb contains a desktop file RisuAI.desktop
    # We need to ensure it points to the binary in the nix store.
    sed -i -e "s|Exec=/usr/bin/RisuAI|Exec=$out/bin/RisuAI|" \
           -e "s|Exec=RisuAI|Exec=$out/bin/RisuAI|" \
           $out/share/applications/RisuAI.desktop

    # Create a lowercase symlink for CLI convenience
    ln -s $out/bin/RisuAI $out/bin/risuai
  '';

  meta = with lib; {
    description = "Cross-platform AI chatting software/web application (Linux Desktop)";
    homepage = "https://github.com/kwaroran/RisuAI";
    license = licenses.agpl3Only;
    platforms = platforms.linux;
    maintainers = [ ];
    mainProgram = "risuai";
  };
}
