{
  pkgs,
  inputs ? null,
  config,
  lib,
  ...
}:

let
  # Install upstream base16-shell into a store path, and bundle your custom
  # base16 theme script into scripts/ as part of the same output.
  #
  # We then link the whole directory into ~/.config/base16-shell via `home.file`
  # as a single mapping (avoids nested-file installation issues).
  base16ShellInstalled = pkgs.stdenvNoCC.mkDerivation {
    pname = "base16-shell-installed";
    version = "0";

    src = pkgs.fetchFromGitHub {
      owner = "chriskempson";
      repo = "base16-shell";
      rev = "master";
      sha256 = "sha256-X89FsG9QICDw3jZvOCB/KsPBVOLUeE7xN3VCtf0DD3E=";
    };

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -R ./* "$out"/

      # Bundle your custom theme into the installed scripts directory.
      mkdir -p "$out/scripts"
      cp "${inputs.dotfiles}/base16-shell/base16-neko.sh" "$out/scripts/base16-neko.sh"

      runHook postInstall
    '';
  };

  # Runtime locations where Home Manager agenix materializes secrets.
  # Prefer referencing the declared secret paths so this works across machines/users.
  crushOpenaiKeyFile = config.age.secrets."crush-openai-api-key".path;
  crushGeminiKeyFile = config.age.secrets."crush-gemini-api-key".path;
in

{
  # User-scoped fonts (Home Manager)
  my.home.fonts = {
    enable = true;
    packages = with pkgs; [
      noto-fonts
      dejavu_fonts
      liberation_ttf
      freefont_ttf
      noto-fonts-color-emoji
      nerd-fonts.symbols-only
    ];
  };

  nix = {
    package = lib.mkDefault pkgs.nix;
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  # ---------------------------------------------------------------------------
  # Shell-only: load provider API keys from agenix-decrypted runtime files
  #
  # Crush does not accept file paths for `api_key`; it expects the key string.
  # We therefore export env vars from the decrypted secret files at shell init.
  #
  # NOTE: We use `initContent` with a low order priority to ensure these exports
  # happen BEFORE the `source ~/.zshrc; return` block defined in modules/home/base.nix.
  # ---------------------------------------------------------------------------
  programs.zsh.initContent = lib.mkOrder 400 ''
    # agenix -> env vars for Crush
    if [ -r "${crushOpenaiKeyFile}" ]; then
      export OPENAI_API_KEY="$(tr -d '\n' < "${crushOpenaiKeyFile}")"
    fi

    if [ -r "${crushGeminiKeyFile}" ]; then
      export GEMINI_API_KEY="$(tr -d '\n' < "${crushGeminiKeyFile}")"
    fi
  '';

  imports = [
    ./modules/home/base.nix
    ./modules/home/themes/theme-folder.nix

    # User-scoped fonts + fontconfig (avoid system-wide font cache work at boot)
    ./modules/home/fonts.nix

    # Home Manager package sets
    #
    # Keep the default (portable) Home Manager profile CLI-only.
    # Desktop/WM-specific modules should be imported by a separate desktop profile.
    ./modules/home/packages/base.nix

    ./modules/home/powershell.nix

    # ai.md: link shared AI skills/rules from a local checkout (optional, private)
    ./modules/home/ai.nix

    # Hivecom depot upload (script + macOS keybinds)
    ./modules/home/depot.nix
  ];

  # ---------------------------------------------------------------------------
  # Hivecom depot upload
  #
  # Installs `depot-upload` and, on macOS, binds Cmd+Alt+Shift+3/4/6 (full /
  # region screenshot / clipboard) to upload and copy the resulting URL.
  # The Linux WM binds (Plasma/Hyprland) are not wired yet; this just adds the
  # command there.
  # ---------------------------------------------------------------------------
  my.home.depot = {
    enable = true;
    keybinds.enable = true;
  };

  # ---------------------------------------------------------------------------
  # agenix (Home Manager): decrypt secrets at activation time (not in the store)
  #
  # Identity configuration:
  # - The Home Manager agenix service runs as your user, so it must be able to read
  #   the identity file.
  # - `/etc/ssh/ssh_host_ed25519_key` is root-only; keep a user-owned copy for HM:
  #
  #     sudo install -m 0400 -o zealsprince -g users \
  #       /etc/ssh/ssh_host_ed25519_key \
  #       /home/zealsprince/.config/agenix/identities/ssh_host_ed25519_key
  #
  # - This enables non-interactive decryption at activation time even if your user
  #   SSH key is passphrase-protected.
  # ---------------------------------------------------------------------------
  age.identityPaths = [
    "${config.home.homeDirectory}/.config/agenix/identities/ssh_host_ed25519_key"
  ];

  # Secrets (encrypted files in-repo)
  # ---------------------------------------------------------------------------
  age.secrets = {
    "crush-openai-api-key" = {
      file = ./secrets/crush-openai-api-key.age;
    };

    "crush-gemini-api-key" = {
      file = ./secrets/crush-gemini-api-key.age;
    };
  };

  # Allow Home Manager's Zsh module (completions/plugins/aliases), while still using your dotfiles
  # as the entrypoint via the bridge configured in `.nixos/modules/home/base.nix`.

  # ---------------------------------------------------------------------------
  # base16-shell (terminal palette helper)
  #
  # Provide an upstream base16-shell checkout under:
  #   ~/.config/base16-shell
  #
  # The custom theme `base16-neko.sh` is bundled into the derivation output
  # under scripts/ so we only need a single directory link here.
  # ---------------------------------------------------------------------------
  home.file.".config/base16-shell".source = base16ShellInstalled;

  # ---------------------------------------------------------------------------
  # Link CLI dotfiles into $HOME (zsh, tmux, vim, and scripts)
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Alacritty
  #
  # Link Alacritty config from the dotfiles flake input into the standard
  # XDG config location used by Alacritty on Linux:
  #   ~/.config/alacritty/alacritty.toml
  # ---------------------------------------------------------------------------
  home.file.".config/alacritty/alacritty.toml".source = inputs.dotfiles + "/.alacritty.toml";
  # Zsh is sourced from the dotfiles repo directly (symlinked), not generated by Home Manager.
  # NOTE: The `inputs.dotfiles` flake input must be configured in `flake.nix` for this to work in pure eval.
  home.file.".zshrc".source = inputs.dotfiles + "/zsh/.zshrc";
  home.file.".p10k.zsh".source = inputs.dotfiles + "/zsh/.p10k.zsh";
  home.file.".dircolors".source = inputs.dotfiles + "/zsh/.dircolors";
  home.file.".osxcolors".source = inputs.dotfiles + "/zsh/.osxcolors";

  # IMPORTANT:
  # Do NOT have Home Manager manage anything under `~/.dotfiles/*`.
  # `~/.dotfiles` is your git working tree; if Home Manager manages it, it will
  # replace tracked files with symlinks into the Nix store (breaking the repo).
  #
  # If you need helper shims (e.g. `nix.zsh`), source them directly from the repo
  # via `~/.zshrc` (which we already symlink from `inputs.dotfiles`).

  home.file.".tmux.conf".source = inputs.dotfiles + "/tmux/.tmux.conf";

  home.file.".vimrc".source = inputs.dotfiles + "/vim/.vimrc";

  # Ensure Vim can find custom colorschemes via :colorscheme
  # by placing them under ~/.vim/colors/
  home.file.".vim/colors".source = inputs.dotfiles + "/vim/colors";

  # vim-plug bootstrap: install `plug.vim` into ~/.vim/autoload so Vim can run `plug#begin()`.
  #
  # This is the standard path vim-plug expects for classic Vim (not Neovim):
  #   ~/.vim/autoload/plug.vim
  home.file.".vim/autoload/plug.vim".source = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim";
    sha256 = "sha256-4JmeVzBIZedfWxXuhjfcTOW6lZF1V/OPfLY9RUtTz7Q=";
  };

  # Install custom scripts to ~/.local/bin (on PATH for most setups)
  home.file.".local/bin" = {
    source = inputs.dotfiles + "/bin";
    recursive = true;
    executable = true;
  };

  # ---------------------------------------------------------------------------
  # Zed
  # ---------------------------------------------------------------------------
  # Seed-only config: copy upstream once, then leave user edits alone.
  # An `.upstream` sidecar is refreshed every activation so the latest
  # dotfiles version can be diffed against the live file when pulling in
  # new defaults manually:
  #   diff ~/.config/zed/settings.json ~/.config/zed/settings.json.upstream
  home.activation.installZedConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p $HOME/.config/zed

    # Personal Claude Code config dir, kept separate so the personal account can
    # run as its own Zed ACP agent. Work lives in the DEFAULT config (~/.claude)
    # now, the same one bare `claude` and VSCode use, so it needs no dir here.
    mkdir -p $HOME/.claude-personal

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

    seed_mutable "${inputs.dotfiles}/zed/settings.json" "$HOME/.config/zed/settings.json"
    seed_mutable "${inputs.dotfiles}/zed/keymap.json" "$HOME/.config/zed/keymap.json"
  '';

  home.file.".config/zed/themes/neko-dark.json".source =
    inputs.neko-zed-dark + "/themes/neko-dark.json";
  home.file.".config/zed/themes/Matte Black Neko.json".source =
    inputs.dotfiles + "/zed/themes/Matte Black Neko.json";

  # ---------------------------------------------------------------------------
  # Base (cross-platform Home Manager config)
  # ---------------------------------------------------------------------------
  my.home.base = {
    enable = true;

    zsh = {
      enable = true;

      aliases = {
        ll = "ls -l";
        update = "sudo nixos-rebuild switch --flake .";
      };
    };

    git = {
      enable = true;

      # Signing will be configured for OpenPGP (gpg) in the Home Manager base module.
      signingKey = "C6C9724C93A72651A5630079D65684425DD2FF50";

      signCommits = true;

      # Prefer OpenPGP signing (gpg) over 1Password SSH signing.
      use1PasswordSshSigning = false;

      # Preset the GPG passphrase from 1Password at graphical login via a
      # systemd user service. Requires ~/.zsh_op with OP_ITEM and OP_GPG_KEYGRIP.
      presetGpgAtLogin = true;
    };

    ssh = {
      enable = true;
      enableDefaultConfig = false;
      use1PasswordAgent = true;
    };
  };

}
