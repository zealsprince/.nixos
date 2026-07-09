{
  lib,
  appimageTools,
  fetchurl,
  makeDesktopItem,
  runCommand,
  asar,
  writeText,
  python3,
  noto-fonts-color-emoji,
}:

let
  pname = "flex-designer";
  version = "2.2.3";

  src = fetchurl {
    url = "https://github.com/ENIAC-Tech/FlexDesigner/releases/download/${version}/flex-designer-${version}.x86_64.AppImage";
    sha256 = "sha256-0KA9wTSu127Sgl0Qw6fIGz8u09JVLDrKwqxshVZZ0Ow=";
  };

  extracted = appimageTools.extractType2 { inherit pname version src; };

  # The perf monitor uses the systeminformation npm package, which only reads
  # GPU utilization/temperature from nvidia-smi, so AMD cards show N/A forever.
  # Patch its graphics.js inside app.asar to merge amdgpu sysfs metrics.
  patched =
    runCommand "${pname}-${version}-patched"
      {
        nativeBuildInputs = [ asar ];
      }
      ''
        cp -r ${extracted} $out
        chmod -R u+w $out

        asar extract $out/resources/app.asar app

        substituteInPlace app/node_modules/systeminformation/lib/graphics.js \
          --replace-fail \
            'return mergeControllerNvidia(controller, nvidiaData.find((contr) => contr.pciBus.toLowerCase().endsWith(controller.busAddress.toLowerCase())) || {});' \
            'return mergeControllerAmdSysfs(mergeControllerNvidia(controller, nvidiaData.find((contr) => contr.pciBus.toLowerCase().endsWith(controller.busAddress.toLowerCase())) || {}));'
        cat ${./amd-gpu-sysfs.js} >> app/node_modules/systeminformation/lib/graphics.js

        rm -rf $out/resources/app.asar $out/resources/app.asar.unpacked
        # Keep the same set of unpacked modules as the upstream asar (native
        # binaries cannot be loaded from inside the archive).
        asar pack app $out/resources/app.asar \
          --unpack-dir "node_modules/{@img,active-win,axios,electron-color-picker,follow-redirects,form-data,node-hid,proxy-from-env,sharp}"
      '';

  # On startup the app checks that /etc/udev/rules.d/99-flexbar.rules exists
  # and otherwise tries to install it via sudo-prompt (pkexec), which fails
  # inside the sandbox. The FHS env only binds a whitelist of /etc entries, so
  # the host's rules are invisible either way; bind a copy with the exact
  # upstream name and content to satisfy the check. The permissions themselves
  # come from modules/nixos/hardware/flexbar.nix.
  flexbarUdevRules = writeText "99-flexbar.rules" ''
    SUBSYSTEM=="usb", ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bd", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bd", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bf", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="tty", ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bf", MODE="0666", GROUP="plugdev"
  '';

  # The emoji layer is drawn with a hardcoded "Segoe UI Emoji" family. With
  # system fonts present, the failed lookup falls back to a text font whose
  # missing emoji glyphs render as notdef boxes on the device, so ship Noto
  # Color Emoji under that family name.
  segoeUiEmoji =
    runCommand "segoe-ui-emoji-shim"
      {
        nativeBuildInputs = [ (python3.withPackages (ps: [ ps.fonttools ])) ];
      }
      ''
        mkdir -p $out/share/fonts/truetype
        python3 ${./rename-font-family.py} \
          ${noto-fonts-color-emoji}/share/fonts/noto/NotoColorEmoji.ttf \
          "Segoe UI Emoji" \
          $out/share/fonts/truetype/SegoeUIEmoji.ttf
      '';

  desktopItem = makeDesktopItem {
    name = "FlexDesigner";
    desktopName = "FlexDesigner";
    comment = "Flex Designer";
    exec = "flex-designer %U";
    terminal = false;
    categories = [ "Development" ];
  };

in
appimageTools.wrapAppImage {
  inherit pname version;
  src = patched;

  extraPkgs =
    pkgs: with pkgs; [
      xdotool
      vips
      (python3.withPackages (ps: [ ps.pyaudio ]))
      portaudio
      lm_sensors
      pciutils
      # Font listing scans /usr/share/fonts inside the FHS env (via
      # @napi-rs/canvas), so system fonts must be provided here or the app
      # only sees its bundled icon font and text widgets render nothing.
      dejavu_fonts
      liberation_ttf
      freefont_ttf
      noto-fonts-color-emoji
      segoeUiEmoji
    ];

  profile = ''
    export FONTCONFIG_FILE=/etc/fonts/fonts.conf
  '';

  extraBwrapArgs = [
    "--ro-bind-try ${flexbarUdevRules} /etc/udev/rules.d/99-flexbar.rules"
  ];

  extraInstallCommands = ''
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
