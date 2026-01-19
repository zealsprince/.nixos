{
  pkgs,
  inputs ? null,
  config,
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
in

{
  # User-scoped fonts (Home Manager)
  my.home.fonts = {
    # enable = true;
    # Keep the set small (DejaVu + a few nice defaults + emoji).
    # Override here if you want to add/remove fonts later.
    # packages = with pkgs; [ dejavu_fonts liberation_ttf freefont_ttf noto-fonts-color-emoji ];
  };

  imports = [
    ./modules/home/base.nix

    # Crush (Home Manager module from NUR)
    inputs.nur.legacyPackages.x86_64-linux.repos.charmbracelet.modules.homeManager.crush

    # User-scoped fonts + fontconfig (avoid system-wide font cache work at boot)
    ./modules/home/fonts.nix

    # Home Manager package sets
    #
    # Keep the default (portable) Home Manager profile CLI-only.
    # Desktop/WM-specific modules should be imported by a separate desktop profile.
    ./modules/home/packages/base.nix

    ./modules/home/powershell.nix
  ];

  # ---------------------------------------------------------------------------
  # sops-nix (Home Manager): decrypt secrets at activation time (not in the store)
  # ---------------------------------------------------------------------------
  sops = {
    defaultSopsFile = ./secrets/secrets.yaml;

    # Per-system approach: each machine has its own age keypair.
    #
    # This points sops-nix at the local private key file. It must exist on each
    # system that needs to decrypt secrets.
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

    # Decrypt provider API keys for Crush at activation time.
    secrets."crush/openai_api_key" = { };
    secrets."crush/gemini_api_key" = { };
  };

  # Allow Home Manager's Zsh module (completions/plugins), while still using your dotfiles
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
  # Crush (via NUR module): user-scoped configuration
  #
  # IMPORTANT:
  # - Do not inline API keys here; that would put secrets into the Nix store.
  # - Instead we read it from the sops-nix-managed secret file at activation time.
  # ---------------------------------------------------------------------------
  programs.crush = {
    enable = true;

    settings = {
      providers = {
        # Ollama (local models)
        #
        # Crush can talk to Ollama via its OpenAI-compatible endpoint.
        # By convention, we present it as an OpenAI provider pointing at localhost.
        #
        # Note:
        # - `api_key` is not required for Ollama, but some OpenAI clients require it to be set.
        # - Model `id`s must match what `ollama list` shows (e.g. `qwen2.5-coder:latest`).
        #
        # Fetch the models via `ollama run <model>`..
        ollama = {
          id = "ollama";
          name = "Ollama";
          base_url = "http://127.0.0.1:11434/v1";
          type = "openai";

          # Dummy value for OpenAI-compatible clients.
          api_key = "ollama";

          models = [
            {
              id = "qwen2.5-coder:7b";
              name = "qwen2.5-coder:7b";
            }
            {
              id = "qwen3-vl:8b";
              name = "qwen3-vl:8b";
            }
            {
              id = "devstral-small-2:latest";
              name = "devstral-small-2:latest";
            }
          ];
        };

        openai = {
          id = "openai";
          name = "OpenAI";
          base_url = "https://api.openai.com/v1";
          type = "openai";

          # sops-nix writes the decrypted contents to a root-owned runtime file.
          # This path is a plain string and won't copy the secret into the store.
          api_key = "file:${config.sops.secrets."crush/openai_api_key".path}";

          models = [
            {
              id = "gpt-5.2";
              name = "GPT-5.2";
            }
            {
              id = "gpt-5.2-pro";
              name = "GPT-5.2 Pro";
            }
            {
              id = "gpt-5.2-codex";
              name = "GPT-5.2 Codex";
            }
            {
              id = "gpt-5";
              name = "GPT-5";
            }
            {
              id = "gpt-5-mini";
              name = "GPT-5 Mini";
            }
            {
              id = "gpt-5-nano";
              name = "GPT-5 Nano";
            }
            {
              id = "o4-mini";
              name = "GPT-o4 Mini";
            }
          ];
        };

        gemini = {
          id = "gemini";
          name = "Gemini";
          type = "gemini";

          # sops-nix writes the decrypted contents to a root-owned runtime file.
          # This path is a plain string and won't copy the secret into the store.
          api_key = "file:${config.sops.secrets."crush/gemini_api_key".path}";

          models = [
            {
              id = "gemini-3-pro-preview";
              name = "Gemini 3 Pro Preview";
            }
            {
              id = "gemini-3-flash-preview";
              name = "Gemini 3 Flash Preview";
            }
            {
              id = "gemini-2.5-pro";
              name = "Gemini 2.5 Pro";
            }
            {
              id = "gemini-2.5-flash";
              name = "Gemini 2.5 Flash";
            }
          ];
        };
      };

      options = {
        tui = {
          compact_mode = true;
        };
        debug = false;
      };
    };
  };

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
  # Base (cross-platform Home Manager config)
  # ---------------------------------------------------------------------------
  my.home.base = {
    enable = true;

    # Keep these explicit so the profile remains portable and predictable.
    username = "zealsprince";
    homeDirectory = "/home/zealsprince";
    stateVersion = "25.11";

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
    };

    ssh = {
      enable = true;
      enableDefaultConfig = false;
      use1PasswordAgent = true;
      onePasswordAgentSock = "~/.1password/agent.sock";
    };
  };

}
