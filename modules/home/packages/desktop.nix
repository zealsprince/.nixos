{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  inputs,
  ...
}:

let
  spotiflac = pkgs.callPackage ../../../pkgs/spotiflac/default.nix { };

  # rox ships its icon as `Icon=rox`, but "rox" is also the ROX-Filer file
  # manager, and icon theme sets (BeautySolar, Tela, etc.) alias that name to
  # a file-manager glyph. The active theme wins over hicolor, so KDE draws the
  # file-manager icon instead of rox's own. Rename the icon to a unique
  # `rox-music` no theme claims and repoint the .desktop at it, so lookup
  # falls through to rox's hicolor art. Binary and WM class stay `rox`.
  # symlinkJoin only relinks share/, so the rust build is untouched/cached.
  rox = pkgs.symlinkJoin {
    name = "rox";
    paths = [ inputs.rox.packages.${pkgs.stdenv.hostPlatform.system}.rox ];
    postBuild = ''
      icons=$out/share/icons/hicolor/scalable/apps
      rox_svg=$(readlink -f "$icons/rox.svg")
      rm "$icons/rox.svg"
      ln -s "$rox_svg" "$icons/rox-music.svg"

      if [ -e "$out/share/pixmaps/rox.png" ]; then
        rox_png=$(readlink -f "$out/share/pixmaps/rox.png")
        rm "$out/share/pixmaps/rox.png"
        ln -s "$rox_png" "$out/share/pixmaps/rox-music.png"
      fi

      entry=$out/share/applications/rox.desktop
      real=$(readlink -f "$entry")
      rm "$entry"
      sed 's/^Icon=rox$/Icon=rox-music/' "$real" > "$entry"
    '';
  };

  # streamrip from the upstream dev branch (flake input) instead of the
  # v2.1.0 tag nixpkgs builds. The nixpkgs patch and ffmpeg path sed still
  # apply on dev.
  streamrip-dev = pkgs.streamrip.overridePythonAttrs (old: {
    version = "2.2.0-dev";
    src = inputs.streamrip-src;
    # Stale upstream test: expects genre 'Pop', fixture data says 'Rock'.
    disabledTests = (old.disabledTests or [ ]) ++ [ "test_album_metadata_qobuz" ];
  });

  # PhotoGIMP as a second launcher next to stock GIMP: same gimp binary,
  # but GIMP3_DIRECTORY points it at its own config dir so the Photoshop
  # layout and stock GIMP settings never touch each other. The config is
  # seeded once by the seedPhotoGimpConfig activation below; GIMP rewrites
  # its rc files at runtime, so they have to stay mutable copies.
  # Affinity's wine runtime is built from affinity-nix's pinned nixpkgs-wine
  # (glibc 2.40 today), but wine picks up GPU drivers from the host's
  # /run/opengl-driver, where mesa tracks current nixpkgs. Once host mesa
  # needs a glibc symbol the pinned runtime lacks (GLIBC_ABI_GNU2_TLS), every
  # Vulkan ICD fails to load inside the sandbox: DXGI enumerates no adapters,
  # hardware acceleration dies, and files that need a render device livelock
  # the UI thread on open. Point the Vulkan loader at a mesa built from the
  # same nixpkgs as the wine runtime so the ABI matches even when the fork
  # bumps its pin.
  affinity-mesa =
    (import inputs.affinity-nix.inputs.nixpkgs-wine {
      inherit (pkgs.stdenv.hostPlatform) system;
    }).mesa.drivers;
  affinity-icds = lib.concatStringsSep ":" [
    "${affinity-mesa}/share/vulkan/icd.d/radeon_icd.x86_64.json"
    "${affinity-mesa}/share/vulkan/icd.d/intel_icd.x86_64.json"
  ];

  # affinity-nix's runner force-runs `wineboot --update` on every launch, which
  # reinstalls wine.inf against the read-only overlay. Under experimental wow64
  # some 32-bit child registrations (e.g. iexplore /RegServer) fail and pop a
  # "rundll32.exe - This application could not be started" dialog, twice, every
  # launch, plus the "Wine configuration is being updated" popup. Removing
  # DISPLAY for just the wineboot call makes wine's null graphics driver swallow
  # those MessageBoxes (wineboot's real registry/dll work is unaffected, and the
  # app itself still launches with DISPLAY). Rebuild the runner from a patched
  # source copy; everything else in the graph (base prefix, wine, apl) is cached.
  affinity-nix-patched-src = pkgs.runCommand "affinity-nix-runner-patched" { } ''
    cp -r ${inputs.affinity-nix} $out
    chmod -R u+w $out
    substituteInPlace $out/crates/runner/src/main.rs \
      --replace-fail 'cmd!(WINE, "wineboot", "--update")' \
        'cmd!(WINE, "wineboot", "--update").env_remove("DISPLAY").env_remove("WAYLAND_DISPLAY")'
  '';
  affinity-v3-patched = pkgs.callPackage "${affinity-nix-patched-src}/packages/affinity-v3/package.nix" {
    inputs = inputs.affinity-nix.inputs;
    stdPath =
      p: [ p.zenity p.curl p.zstd p.coreutils p.gnused p.gnugrep p.wget p.busybox ];
  };

  affinity-v3-gpu = pkgs.symlinkJoin {
    name = "affinity-v3-gpu";
    paths = [ affinity-v3-patched ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/affinity-v3 \
        --set VK_DRIVER_FILES "${affinity-icds}" \
        --set VK_ICD_FILENAMES "${affinity-icds}"
      # The bundled desktop item Execs the unwrapped runner by absolute store
      # path, which would bypass the wrapper. Repoint it at the wrapped bin.
      entry=$out/share/applications/affinity-v3.desktop
      real=$(readlink -f "$entry")
      rm "$entry"
      sed "s|Exec=[^ ]*/bin/affinity-v3|Exec=$out/bin/affinity-v3|" "$real" > "$entry"
    '';
  };

  photogimp = pkgs.symlinkJoin {
    name = "photogimp";
    paths = [
      (pkgs.writeShellScriptBin "photogimp" ''
        export GIMP3_DIRECTORY="''${XDG_CONFIG_HOME:-$HOME/.config}/PhotoGIMP"
        exec ${pkgs-unstable.gimp-with-plugins}/bin/gimp "$@"
      '')
      (pkgs.makeDesktopItem {
        name = "photogimp";
        desktopName = "PhotoGIMP";
        genericName = "Image Editor";
        comment = "GIMP with a Photoshop-style layout and shortcuts";
        exec = "photogimp %U";
        icon = "photogimp";
        categories = [
          "Graphics"
          "2DGraphics"
          "RasterGraphics"
          "GTK"
        ];
      })
      (pkgs.runCommand "photogimp-icons" { } ''
        mkdir -p $out/share
        cp -r ${inputs.photogimp}/.local/share/icons $out/share/icons
      '')
    ];
  };
in

let
  cfg = config.my.home.packages.desktop;
in
{
  options.my.home.packages.desktop = {
    enable = lib.mkEnableOption "Desktop (GUI) user package set for Home Manager";

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Extra desktop packages to add on top of the default desktop set.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Desktop/GUI applications that are user-scoped (Home Manager).
    #
    # Keep this module DE-agnostic. If you later need Plasma-only user packages,
    # add a sibling module (e.g. `packages/desktop.plasma.nix`) gated on your WM.
    home.packages =
      (with pkgs; [
        # More heafty CLI tools
        ffmpeg-full
        whisper-cpp-vulkan

        # Essentials
        resources
        obsidian
        libreoffice-still
        deskflow

        # Dropbox (Maestral) + Dolphin service-menu helper runtime deps
        maestral
        maestral-gui

        coreutils # realpath
        xdg-utils # xdg-open
        libnotify # notify-send

        # Clipboard helpers for "Copy Dropbox shared link (via Maestral)" Dolphin action:
        # - Wayland: wl-copy
        # - X11: xclip
        wl-clipboard
        xclip

        deluge
        rox
        syncplay
        pkgs-unstable.plezy
        opensnitch-ui
        syncthing

        # Hate it but I need it
        spotify

        # Tidal yippie
        tonearm
        sone
        streamrip-dev
        # Needs --no-sandbox as a real argument: the in-app sandbox setting
        # applies too late, Chromium still spawns the sandboxed zygote and
        # renderers forked from it die on /dev/shm (white screen).
        (symlinkJoin {
          name = "tidal-hifi";
          paths = [ tidal-hifi ];
          nativeBuildInputs = [ makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/tidal-hifi --add-flags "--no-sandbox"
          '';
        })

        # Development tools
        pkgs-unstable.zed-editor-fhs
        bruno
        pkgs-unstable.vscode
        firefox
        firefox-devedition
        ungoogled-chromium
        dbeaver-bin
        chatbox
        unityhub
        godot
        love

        # Reverse engineering
        qFlipper
        cutter
        ghidra

        # Creative tools
        pkgs-unstable.gimp-with-plugins
        photogimp
        affinity-v3-gpu
        pkgs-unstable.pureref
        darktable
        (blender.override { rocmSupport = true; })
        freecad
        openscad
        openscad-lsp
        krita
        aseprite
        prusa-slicer
        handbrake
        video-trimmer
        davinci-resolve-studio

        audacity
        pkgs-unstable.vcv-rack
        renoise

        # Social & Work
        hexchat
        halloy
        pkgs-unstable.ferdium
        pkgs-unstable.discord
        pkgs-unstable.signal-desktop
        pkgs-unstable.element-desktop
        teamspeak3
        teamspeak6-client
        pkgs-unstable.zoom-us
        pkgs-unstable.teams-for-linux
        slack

        # Streaming & Recording
        pkgs-unstable.obs-studio
        webcamoid
        gopro-tool

        # Gaming & Wine
        pkgs-unstable.wine-staging
        heroic
        lutris
        prismlauncher
        pkgs-unstable.r2modman
        gamescope
        mangohud
        osu-lazer-bin
      ])
      ++ cfg.packages;

    # VSCode: the editor is installed as a package above (pkgs-unstable.vscode)
    # and extensions are managed by VSCode itself, from the marketplace. Native
    # extension binaries work because nix-ld is enabled.
    #
    # NOTE: deliberately no `programs.vscode` here. Declaring even a single
    # extension through it makes Home Manager wipe and regenerate
    # ~/.vscode/extensions/extensions.json whenever the extension derivations
    # rebuild (any flake.lock bump), which resurrects every stale extension
    # folder on disk and resets extension state. Likewise no `userSettings`,
    # which would lock settings.json as a read-only nix-store symlink. We keep
    # all VSCode state mutable and only patch the dynamic pwsh path below.

    # Seed-only config: copy upstream once, then leave user edits alone.
    # An `.upstream` sidecar is refreshed every activation for manual diffing:
    #   diff ~/.config/Code/User/settings.json ~/.config/Code/User/settings.json.upstream
    home.activation.seedVSCodeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings="$HOME/.config/Code/User/settings.json"
      mkdir -p "$(dirname "$settings")"

      seed_mutable() {
        local src=$1
        local dst=$2

        # Cleanup: remove symlinks from previous (immutable) config style
        if [ -L "$dst" ]; then rm "$dst"; fi

        # Always refresh upstream reference for manual diffing
        cp -f "$src" "$dst.upstream"
        chmod u+w "$dst.upstream"

        # Seed once: only write if user has no file yet
        if [ ! -e "$dst" ]; then
          cp "$src" "$dst"
          chmod u+w "$dst"
        fi
      }

      seed_mutable "${inputs.dotfiles}/vscode/settings.json" "$settings"
    '';

    # Seed-only PhotoGIMP config for the launcher above. Copied once so GIMP
    # can freely rewrite shortcuts/session state afterwards. To re-apply the
    # upstream layout, delete ~/.config/PhotoGIMP and reactivate. Upstream
    # ships these as GIMP 3.0 files; GIMP 3.2 reads them fine.
    home.activation.seedPhotoGimpConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      photogimp_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/PhotoGIMP"
      if [ ! -e "$photogimp_dir" ]; then
        mkdir -p "$photogimp_dir"
        cp -r ${inputs.photogimp}/.config/GIMP/3.0/. "$photogimp_dir/"
        chmod -R u+w "$photogimp_dir"
      fi
    '';

    # The PowerShell extension only probes a hard-coded list of distro paths
    # and doesn't search $PATH, so point it at the Nix-provided pwsh. Rather
    # than letting HM manage (lock) settings.json, patch just this key into
    # the user's mutable settings.json on each rebuild.
    home.activation.patchVSCodePwshPath = lib.hm.dag.entryAfter [ "seedVSCodeConfig" ] ''
      settings="$HOME/.config/Code/User/settings.json"
      mkdir -p "$(dirname "$settings")"

      # Drop any prior managed symlink so the file becomes user-owned again.
      if [ -L "$settings" ]; then rm "$settings"; fi
      # Fallback: seed activation should have created this, but guard anyway.
      if [ ! -e "$settings" ]; then echo '{}' > "$settings"; chmod u+w "$settings"; fi

      # Skip silently if the file isn't plain JSON (e.g. user added JSONC
      # comments); never clobber a settings file we can't safely parse.
      if ${pkgs.jq}/bin/jq -e . "$settings" >/dev/null 2>&1; then
        tmp="$(mktemp)"
        ${pkgs.jq}/bin/jq \
          --arg pwsh "${pkgs.powershell}/bin/pwsh" \
          '.["powershell.powerShellAdditionalExePaths"]["PowerShell (Nix)"] = $pwsh
           | .["powershell.powerShellDefaultVersion"] = "PowerShell (Nix)"' \
          "$settings" > "$tmp" && mv "$tmp" "$settings"
        chmod u+w "$settings"
      else
        echo "patchVSCodePwshPath: $settings is not plain JSON, skipping pwsh patch" >&2
      fi
    '';
  };
}
