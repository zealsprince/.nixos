{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  inputs,
  ...
}:

let
  plezy = inputs.mio19-nurpkgs.packages.${pkgs.stdenv.hostPlatform.system}.plezy;
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
        tauon
        plezy
        opensnitch-ui
        syncthing

        # Hate it but I need it
        spotify

        # Development tools
        pkgs-unstable.zed-editor-fhs
        bruno
        vscode
        firefox-devedition
        ungoogled-chromium
        dbeaver-bin
        chatbox
        unityhub
        godot
        love

        # Reverse engineering
        cutter
        ghidra

        # Creative tools
        inputs.affinity-nix.packages.${pkgs.stdenv.hostPlatform.system}.v3
        pureref
        darktable
        blender-hip
        krita
        handbrake
        davinci-resolve
        audacity
        vcv-rack
        renoise

        # Social & Work
        hexchat
        ferdium
        pkgs-unstable.discord
        teamspeak3
        pkgs-unstable.teams-for-linux
        slack

        # Streaming & Recording
        pkgs-unstable.obs-studio
        gopro-tool
        gpu-screen-recorder-gtk

        # Gaming & Wine
        heroic
        lutris
        prismlauncher
        r2modman
        gamescope
        mangohud
        osu-lazer-bin
      ])
      ++ cfg.packages;
  };
}
