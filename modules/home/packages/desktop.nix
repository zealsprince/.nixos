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
        syncplay
        pkgs-unstable.plezy
        opensnitch-ui
        syncthing

        # Hate it but I need it
        spotify
        spotiflac

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
        cutter
        ghidra

        # Creative tools
        inputs.affinity-nix.packages.${pkgs.stdenv.hostPlatform.system}.affinity-v3
        pureref
        darktable
        (blender.override { rocmSupport = true; })
        krita
        handbrake
        video-trimmer
        davinci-resolve-studio

        audacity
        vcv-rack
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

    # VSCode: manage extensions via Home Manager.
    # The editor itself is installed as a package above (pkgs-unstable.vscode).
    programs.vscode = {
      enable = true;
      package = pkgs-unstable.vscode;

      profiles.default.extensions = with pkgs.vscode-extensions; [
        # .NET / C# development
        ms-dotnettools.csharp

        # PowerShell (pwsh installed via modules/home/powershell.nix)
        ms-vscode.powershell
      ];

      # NOTE: deliberately no `userSettings` here. Setting it makes Home
      # Manager write settings.json as a read-only nix-store symlink, which
      # VSCode surfaces as a locked/"managed" config. We keep settings.json a
      # mutable, user-owned file and only patch the dynamic pwsh path below.
    };

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
