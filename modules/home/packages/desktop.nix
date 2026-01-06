{ config, pkgs, lib, inputs, ... }:

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

        # Essentials
        dropbox
        deluge
        tauon
        opensnitch-ui

        # Hate it but I need it
        spotify

        # Development tools
        zed-editor-fhs
        vscode
        obsidian
        firefox-devedition
        ungoogled-chromium
        dbeaver-bin
        chatbox
        unityhub
        godot
        love

        # Creative tools
        inputs.affinity-nix.packages.${pkgs.stdenv.hostPlatform.system}.v3
        blender-hip
        krita
        renoise
        kdePackages.kdenlive
        davinci-resolve

        # Social & Work
        hexchat
        ferdium
        discord
        teamspeak3
        teams-for-linux
        slack

        # Streaming
        obs-studio

        # Gaming & Wine
        lutris
        prismlauncher
        gamescope
      ])
      ++ cfg.packages;
  };
}
