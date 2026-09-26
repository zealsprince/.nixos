{
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
  buildFHSEnv,
  runCommand,
  patchelf,
  bzip2,
  curl,
  dotnetCorePackages,
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

  # GMRT's native tools (AssetCompiler, gmir2llvm, gmrt_generic) link Debian's
  # libcurl-gnutls.so.4 and require its CURL_GNUTLS_3 symbol version. The TLS
  # backend doesn't change the libcurl API, so build the regular curl with that
  # version name and hand it over under Debian's soname.
  curlGnutlsCompat =
    let
      curl' = curl.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace lib/libcurl.vers.in \
            --replace-fail '@CURL_LIBCURL_VERSIONED_SYMBOLS_SONAME@' '3'
        '';
        configureFlags = (old.configureFlags or [ ]) ++ [ "--enable-versioned-symbols=GNUTLS_" ];
        doCheck = false;
        doInstallCheck = false;
      });
    in
    runCommand "curl-gnutls-soname" { nativeBuildInputs = [ patchelf ]; } ''
      mkdir -p $out/lib
      cp ${lib.getLib curl'}/lib/libcurl.so.4.* $out/lib/libcurl-gnutls.so.4
      chmod u+w $out/lib/libcurl-gnutls.so.4
      patchelf --set-soname libcurl-gnutls.so.4 $out/lib/libcurl-gnutls.so.4
    '';

  # Ubuntu target builds package the game as an AppImage. Igor runs
  # `linuxdeploy --appimage-extract`, then runs the extracted linuxdeploy
  # chrooted into the Steam Runtime sysroot, then appimagetool with
  # --appimage-extract-and-run. Both have to be the raw upstream AppImages,
  # since those flags are handled by the AppImage runtime itself.
  linuxdeploy = fetchurl {
    url = "https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-x86_64.AppImage";
    hash = "sha256-wgzXHjpOO4DDSDzveTzaP06ZCsoUAU0jxUTKPOEnC00=";
  };

  appimagetool = fetchurl {
    url = "https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage";
    hash = "sha256-7UzoTw2cr/ZvULzKb/bzWq5UzoE1QIs/ozq/w8s4TrA=";
  };

  appimageBuildTools = runCommand "gamemaker-appimage-tools" { } ''
    install -Dm755 ${linuxdeploy} $out/bin/linuxdeploy
    install -Dm755 ${appimagetool} $out/bin/appimagetool
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

      # Ubuntu target builds. The sysroot itself comes from the host at
      # /opt/steam-runtime (see modules/nixos/packages/custom.nix).
      appimageBuildTools
      rsync

      # GMRT toolchain natives (AssetCompiler, gmir2llvm, bundled gensquashfs).
      curlGnutlsCompat
      libselinux

      # linuxdeploy's excludelist keeps these out of the game AppImage and
      # expects the host to have them, so games run from the IDE need them here.
      e2fsprogs
      gmp
      libgpg-error
      libxcb

      # GMRT game AppImages bundle everything but SDL2.
      SDL2
    ];

  runScript = "${unpacked}/opt/GameMaker-Beta/GameMaker";

  # The IDE is self-contained, but the GMRT toolchain it downloads (gmrt, gmc,
  # csc, ...) is framework-dependent on .NET 8 and doesn't roll forward to a
  # newer major. Pin it here so a global DOTNET_ROOT pointing elsewhere doesn't
  # leak in.
  #
  # GMRT's Run job executes the game AppImage directly, and fusermount can't
  # work inside the sandbox, so have the AppImage runtime extract instead.
  #
  # GMRT games hand Dawn an X11 surface no matter what SDL picked. nixpkgs'
  # SDL2 is sdl2-compat, which prefers Wayland, and the game then segfaults in
  # XGetWindowAttributes. Ubuntu's SDL2 defaults to X11, so match that.
  profile = ''
    export DOTNET_ROOT=${dotnetCorePackages.runtime_8_0}/share/dotnet
    export APPIMAGE_EXTRACT_AND_RUN=1
    export SDL_VIDEODRIVER=x11
  '';

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
