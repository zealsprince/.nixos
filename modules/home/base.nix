{
  config,
  pkgs,
  lib,
  ...
}:

# NOTE:
# This module intentionally keeps `~/.zshrc` itself in the external `.dotfiles` repo
# (symlinked by `.nixos/home.nix`). The “NixOS best way” we apply here is to stop
# imperative plugin cloning (e.g. `zsh/plugins.sh`) by having Home Manager provide
# the common Zsh theme + plugins as packages and export stable entrypoint paths
# via environment variables for dotfiles to consume (portable hybrid approach).

let
  cfg = config.my.home.base;

  # Ensure gpg-agent knows which pinentry to use.
  # Prefer a deterministic absolute store path (works in pure/pinned environments).
  pinentryQt = lib.getExe pkgs.pinentry-qt;

  # Used by SSH matchBlocks below; keep it overridable and cross-platform.
  onePasswordAgentSockDefault = "~/.1password/agent.sock";

  # Home Manager is deprecating relative `programs.zsh.dotDir` paths.
  # Use an XDG-aware absolute path to keep ~/.zshrc free for dotfiles symlink.
  zshDotDir = "${config.xdg.configHome}/zsh";

  # ---------------------------------------------------------------------------
  # Zsh plugin/theme entrypoint paths (exported for dotfiles usage)
  #
  # Dotfiles can source these if present, otherwise fall back to OMZ/custom dirs.
  # We keep these as derivation paths (store paths) so they're deterministic.
  # ---------------------------------------------------------------------------
  p10kDir = "${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k";
  p10kTheme = "${p10kDir}/powerlevel10k.zsh-theme";

  autosuggestionsPlugin = "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh";

  # Many distros package syntax-highlighting under this canonical name, but the
  # exact path can vary. We'll export a best-effort entrypoint and let dotfiles
  # handle absence gracefully.
  syntaxHighlightingPlugin = "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh";

  codexPlugin = "${pkgs.fetchFromGitHub {
    owner = "tom-doerr";
    repo = "zsh_codex";
    rev = "6ede649f1260abc5ffe91ef050d00549281dc461";
    sha256 = "1vllp87ya30jyq13x9qwg30mklh17h1648na0qmi742sn09bwycv";
  }}";

  codexPython = pkgs.python3.withPackages (ps: [ ps.openai ]);
in
{
  options.my.home.base = {
    enable = lib.mkEnableOption "Base Home Manager configuration (shell, git, ssh, baseline user packages)";

    username = lib.mkOption {
      type = lib.types.str;
      default = config.home.username or "zealsprince";
      description = "Username for the Home Manager profile.";
    };

    homeDirectory = lib.mkOption {
      type = lib.types.str;
      default = config.home.homeDirectory or "/home/${cfg.username}";
      description = "Home directory for the Home Manager profile.";
    };

    stateVersion = lib.mkOption {
      type = lib.types.str;
      default = config.home.stateVersion or "25.11";
      description = "Home Manager state version.";
    };

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Extra user-scoped packages to install.";
    };

    # ---- Zsh ----
    zsh = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Zsh configuration.";
      };

      historySize = lib.mkOption {
        type = lib.types.int;
        default = 10000;
        description = "Zsh history size.";
      };

      aliases = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {
          ll = "ls -l";
        };
        description = "Shell aliases.";
      };

      enableOhMyZsh = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Oh My Zsh.";
      };

      ohMyZshTheme = lib.mkOption {
        type = lib.types.str;
        default = "robbyrussell";
        description = "Oh My Zsh theme name.";
      };

      ohMyZshPlugins = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "git" ];
        description = "Oh My Zsh plugins.";
      };
    };

    # ---- Git ----
    git = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable git configuration.";
      };

      userName = lib.mkOption {
        type = lib.types.str;
        default = "Andrew Lake";
        description = "Default git author name (user.name).";
      };

      userEmail = lib.mkOption {
        type = lib.types.str;
        default = "andrew@zealsprince.com";
        description = "Default git author email (user.email).";
      };

      signingKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional git signing key (e.g. OpenPGP key id/fingerprint, or SSH public key).";
      };

      signCommits = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to sign commits by default.";
      };

      signingFormat = lib.mkOption {
        type = lib.types.enum [
          "openpgp"
          "ssh"
        ];
        default = "openpgp";
        description = "Git signing format. Use `openpgp` for GPG keys, or `ssh` for SSH-based signing.";
      };

      # When true, configures git to sign via 1Password's op-ssh-sign (SSH format).
      # Only takes effect when `signingFormat = \"ssh\"`.
      use1PasswordSshSigning = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use 1Password's `op-ssh-sign` helper for git commit signing (SSH format).";
      };

      # When enabled, ensures GnuPG tooling is available in the user environment.
      installGpg = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install GnuPG tooling in the user profile to support OpenPGP git signing.";
      };
    };

    # ---- SSH ----
    ssh = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable SSH configuration.";
      };

      enableDefaultConfig = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to let Home Manager generate a default SSH config.";
      };

      use1PasswordAgent = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Configure SSH to use 1Password's agent socket via IdentityAgent.";
      };

      onePasswordAgentSock = lib.mkOption {
        type = lib.types.str;
        default = onePasswordAgentSockDefault;
        description = "Path to the 1Password SSH agent socket.";
      };

      extraMatchBlocks = lib.mkOption {
        type = lib.types.attrs;
        default = { };
        description = "Additional SSH matchBlocks merged into the defaults.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.username = cfg.username;
    home.homeDirectory = cfg.homeDirectory;
    home.stateVersion = cfg.stateVersion;

    programs.home-manager.enable = true;

    # =========================================================================
    #  USER PACKAGES (base / cross-platform)
    # =========================================================================
    home.packages =
      cfg.packages
      ++ (with pkgs; [
        # Per-directory dev toolchain switching (direnv + Nix integration)
        direnv
        nix-direnv

        # Audio CLI utilities (for discovering/setting mic monitor/sidetone)
        alsa-utils # provides `amixer`
        pulseaudio # provides `pactl` (works with PipeWire's PulseAudio compatibility too)
      ])
      ++ (lib.optionals (cfg.git.enable && cfg.git.installGpg && cfg.git.signingFormat == "openpgp") (
        with pkgs;
        [
          gnupg
          pinentry-qt
        ]
      ))
      # Provide Zsh plugin binaries/assets via Nix so dotfiles don't need to clone.
      # Dotfiles may source the entrypoints via env vars exported below.
      ++ (lib.optionals cfg.zsh.enable (
        with pkgs;
        [
          zsh-powerlevel10k
          zsh-autosuggestions
          zsh-syntax-highlighting
        ]
      ));

    # Export stable entrypoint paths for dotfiles to consume (hybrid approach).
    #
    # IMPORTANT: do NOT self-reference `config.home.sessionVariables` here.
    # That creates a recursive definition (sessionVariables depends on itself).
    home.sessionVariables = lib.optionalAttrs cfg.zsh.enable {
      # Dotfiles-consumed plugin entrypoints (portable hybrid approach).
      # The dotfiles repo can source these if present; non-Nix systems can ignore them.
      ZDOTFILES_ZSH_P10K_THEME = p10kTheme;
      ZDOTFILES_ZSH_AUTOSUGGESTIONS = autosuggestionsPlugin;
      ZDOTFILES_ZSH_SYNTAX_HIGHLIGHTING = syntaxHighlightingPlugin;
      ZDOTFILES_ZSH_CODEX = codexPlugin;
      ZSH_CODEX_PYTHON = "${codexPython}/bin/python3";

      # Make nix-direnv use the flake-based fast path by default when possible.
      # (Safe even if you don't use it in a given directory.)
      DIRENV_LOG_FORMAT = "";
    };

    # =========================================================================
    #  GPG / GPG-AGENT (for OpenPGP signing)
    # =========================================================================
    #
    # This ensures:
    # - gpg-agent is enabled for the user
    # - a pinentry program is configured explicitly
    # - loopback pinentry is permitted when needed (e.g. some terminal flows)
    #
    # Note: allowing loopback does not force loopback usage; it only permits it.
    programs.gpg = lib.mkIf (cfg.git.enable && cfg.git.signingFormat == "openpgp") {
      enable = true;
      # Defaults to gpg2 on some systems; set explicitly for clarity/portability.
      package = pkgs.gnupg;
    };

    services.gpg-agent = lib.mkIf (cfg.git.enable && cfg.git.signingFormat == "openpgp") {
      enable = true;

      # Make sure the agent uses a functional pinentry implementation.
      pinentry.package = pkgs.pinentry-qt;

      # Allow loopback for cases where gpg is invoked with --pinentry-mode loopback.
      # This commonly helps with non-GUI/remote/TTY scenarios.
      extraConfig = ''
        pinentry-program ${pinentryQt}
        allow-loopback-pinentry
      '';
    };

    # =========================================================================
    #  DIRENV (per-directory environments) + NIX-DIRENV (fast Nix shells)
    # =========================================================================
    programs.direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    # =========================================================================
    #  ZSH CONFIGURATION (Option B)
    #
    # Home Manager manages the "plumbing" (completion, plugin packages/env, etc),
    # but your dotfiles `~/.zshrc` is the ONLY interactive entrypoint.
    #
    # We achieve this by:
    # - Keeping HM's ZDOTDIR-based setup (dotDir under XDG)
    # - Using `initExtraFirst` to immediately source ~/.zshrc and stop HM from
    #   applying its own theme/plugins/aliases afterward.
    # =========================================================================
    programs.zsh = lib.mkIf cfg.zsh.enable {
      enable = true;

      # Keep HM-managed Zsh state under XDG while leaving ~/.zshrc free for dotfiles.
      dotDir = zshDotDir;

      # HM can still install/provide these; your dotfiles can choose what to use.
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      # IMPORTANT: make dotfiles the entrypoint and short-circuit the rest of HM's init.
      # `initExtraFirst` is deprecated; use `initContent` with `lib.mkBefore`.
      initContent = lib.mkBefore ''
        if [ -r "$HOME/.zshrc" ]; then
          source "$HOME/.zshrc"
          return
        fi
      '';
    };

    # =========================================================================
    #  GIT CONFIGURATION
    # =========================================================================
    programs.git = lib.mkIf cfg.git.enable (
      let
        opSshSign = lib.getExe' pkgs._1password-gui "op-ssh-sign";
      in
      {
        enable = true;

        # Home Manager renamed identity options:
        # - programs.git.userName  -> programs.git.settings.user.name
        # - programs.git.userEmail -> programs.git.settings.user.email
        #
        # IMPORTANT:
        # Use `lib.mkMerge` so we can set identity under `settings.user.*` without
        # hitting Nix duplicate-attribute definition errors, while keeping other
        # git settings in the same final attrset.
        settings = lib.mkMerge [
          {
            user = {
              name = cfg.git.userName;
              email = cfg.git.userEmail;
            };
          }

          {
            commit.gpgsign = cfg.git.signCommits;
            gpg.format = cfg.git.signingFormat;
          }

          (lib.optionalAttrs (cfg.git.signingKey != null) {
            user.signingKey = cfg.git.signingKey;
          })

          (lib.optionalAttrs (cfg.git.signingFormat == "ssh" && cfg.git.use1PasswordSshSigning) {
            "gpg \"ssh\"".program = opSshSign;
          })
        ];
      }
    );

    # =========================================================================
    #  SSH CONFIGURATION
    # =========================================================================
    #
    # IMPORTANT:
    # We intentionally do NOT enable Home Manager's `programs.ssh` here.
    #
    # Home Manager's SSH module manages `~/.ssh/config` as a symlink into the Nix
    # store, and OpenSSH is strict about permissions/ownership on that path. This
    # can trigger:
    #   "Bad owner or permissions on /home/zealsprince/.ssh/config"
    #
    # Instead, we only manage a minimal shared config in the XDG location
    # (`~/.config/ssh/config`) and have a user-owned `~/.ssh/config` include it.

    # -------------------------------------------------------------------------
    # IMPORTANT: Do not let Home Manager manage ~/.ssh/config
    #
    # OpenSSH is strict about ownership/permissions on ~/.ssh/config, and a
    # Home Manager symlink target in the Nix store can trigger:
    #   "Bad owner or permissions on ~/.ssh/config"
    #
    # We instead:
    # - manage a minimal SSH config at the XDG location (only the 1Password agent)
    # - ensure ~/.ssh/config is a regular file (not a symlink) that includes it
    #
    # Host entries should be managed manually in ~/.ssh/config (or in additional
    # include files you control), not in this public repo.
    # -------------------------------------------------------------------------
    # Manage XDG ssh config as a real file with strict permissions.
    #
    # Some clients (e.g. GUI git integrations) are strict about permissions and
    # will reject symlinked configs under ~/.config/ssh/config, similar to how
    # OpenSSH rejects store-owned ~/.ssh/config symlinks.
    #
    # We keep the "global" config minimal and only add the 1Password agent.
    home.activation.ensureXdgSshConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            xdg_dir="${config.xdg.configHome}/ssh"
            xdg_config="$xdg_dir/config"

            mkdir -p "$xdg_dir"
            chmod 700 "$xdg_dir"

            # If it was previously managed by Home Manager as a symlink, remove it.
            if [ -L "$xdg_config" ]; then
              rm -f "$xdg_config"
            fi

            # Rewrite the file deterministically (no public host entries).
            umask 077
            if ${lib.boolToString cfg.ssh.use1PasswordAgent}; then
              cat > "$xdg_config" <<'EOF'
      Host *
        IdentityAgent ${cfg.ssh.onePasswordAgentSock}
      EOF
            else
              : > "$xdg_config"
            fi

            chmod 600 "$xdg_config"
    '';

    home.activation.ensureSshConfigIncludesXdg =
      lib.hm.dag.entryAfter [ "writeBoundary" "ensureXdgSshConfig" ]
        ''
          ssh_dir="$HOME/.ssh"
          ssh_config="$ssh_dir/config"
          xdg_config="${config.xdg.configHome}/ssh/config"

          mkdir -p "$ssh_dir"
          chmod 700 "$ssh_dir"

          # If it's a symlink (e.g. managed by older HM config), remove it.
          if [ -L "$ssh_config" ]; then
            rm -f "$ssh_config"
          fi

          # Create the file if missing, with strict permissions.
          if [ ! -e "$ssh_config" ]; then
            umask 077
            : > "$ssh_config"
          fi
          chmod 600 "$ssh_config"

          # Ensure it includes the XDG-managed config.
          if ! grep -qE '^[[:space:]]*Include[[:space:]]+${config.xdg.configHome}/ssh/config[[:space:]]*$' "$ssh_config"; then
            printf '%s\n' "Include ${config.xdg.configHome}/ssh/config" >> "$ssh_config"
          fi
        '';
  };
}
