{
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
  buildFHSEnv,
  runCommand,
  patchelf,
  bzip2,
}:

let
  pname = "gamemaker-beta";
  version = "2026.100.0.1149";

  # Direct links for each release are on its notes page at
  # https://releases.gamemaker.io (the "Ubuntu Beta" download link).
  src = fetchurl {
    url = "https://gms.yoyogames.com/GameMaker-Beta-${version}.deb";
    hash = "sha256-n3HttYiuqGT7CwGX8FRe8aIO9wQNfwAyHAIGhZKl1GQ=";
  };

  # The .deb is a self-contained .NET app (bundled CoreCLR, SDL2, FNA3D) under
  # /opt/GameMaker-Beta, with x86_64 and aarch64 builds side by side. Unpack
  # it untouched: stripping or patching the bundled runtime isn't worth the
  # risk when the FHS env below supplies the libraries it dlopens.
  unpacked = stdenvNoCC.mkDerivation {
    pname = "${pname}-unpacked";
    inherit version src;

    nativeBuildInputs = [ dpkg ];

    unpackPhase = ''
      dpkg-deb -x $src .
    '';

    installPhase = ''
      mkdir -p $out
      cp -r opt usr/share $out/
    '';

    dontFixup = true;
  };

  # The vendored freetype wants Debian's libbz2.so.1.0. nixpkgs ships that
  # name as a symlink, but the FHS ld cache is keyed by SONAME (libbz2.so.1),
  # so the loader never finds it. Give it a copy that declares the Debian name.
  # The file name has to be unique: the FHS base env already carries bzip2,
  # and its libbz2.so.1.0 symlink wins any path collision.
  bzip2Debian = runCommand "bzip2-debian-soname" { nativeBuildInputs = [ patchelf ]; } ''
    mkdir -p $out/lib
    cp ${lib.getLib bzip2}/lib/libbz2.so.1.0.* $out/lib/libbz2-debian.so.1.0
    chmod u+w $out/lib/libbz2-debian.so.1.0
    patchelf --set-soname libbz2.so.1.0 $out/lib/libbz2-debian.so.1.0
  '';
in
buildFHSEnv {
  inherit pname version;

  targetPkgs =
    pkgs: with pkgs; [
      # Debian Depends: ffmpeg, zip, unzip, libglu1-mesa, zenity. zenity backs
      # the bundled TinyFileDialogs, so without it there are no file pickers.
      ffmpeg
      zip
      unzip
      libGLU
      zenity
      xdg-utils

      # .NET runtime natives (System.Globalization, Security.Cryptography,
      # Net.Security, IO.Compression).
      icu
      openssl
      krb5
      zlib

      # Bundled SDL2 and FNA3D dlopen these for windowing, input, GL/Vulkan
      # and audio.
      libGL
      vulkan-loader
      libx11
      libxext
      libxcursor
      libxi
      libxrandr
      libxrender
      libxfixes
      libxscrnsaver
      libxkbcommon
      wayland
      libdecor
      alsa-lib
      libpulseaudio
      pipewire
      openal
      udev
      dbus
      fontconfig
      freetype

      # The vendored freetype.so the IDE loads for its own font rendering.
      bzip2Debian
      brotli
      libpng

      # Bundled instrumentation engine (code coverage). Links libxml2.so.2,
      # which current libxml2 no longer provides.
      libxml2_13
    ];

  runScript = "${unpacked}/opt/GameMaker-Beta/GameMaker";

  extraInstallCommands = ''
    install -Dm444 ${unpacked}/opt/GameMaker-Beta/GameMaker.png \
      $out/share/icons/hicolor/256x256/apps/${pname}.png

    install -Dm444 ${unpacked}/share/mime/packages/gamemaker-beta.xml \
      $out/share/mime/packages/${pname}.xml

    # Upstream's entry points at /opt, which doesn't exist here.
    mkdir -p $out/share/applications
    sed \
      -e 's|^Exec=.*|Exec=${pname} %F|' \
      -e 's|^Icon=.*|Icon=${pname}|' \
      -e 's|^Name=.*|Name=GameMaker (Beta)|' \
      ${unpacked}/share/applications/GameMaker-Beta.desktop \
      > $out/share/applications/${pname}.desktop
  '';

  meta = {
    description = "GameMaker IDE, Ubuntu beta build";
    homepage = "https://gamemaker.io";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
