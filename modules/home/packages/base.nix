{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  inputs,
  ...
}:

let
  /*
    Base system packages (terminal-friendly)

    Intent:
    - Keep this module safe for terminal-only or server-ish systems.
    - Avoid GUI/desktop apps here (terminals, Steam, editors with GUI, etc.).
    - Prefer keeping “workflow/UI” packages in a desktop-specific module.

    Note:
    - Host-specific tooling should live under `hosts/<host>/...` or a dedicated profile module.
  */
  baseEnabled = config.my.home.base.enable or false;

  # Repo-local custom package (Bitbucket Cloud CLI, gh-like). See pkgs/bkt.
  bkt = pkgs.callPackage ../../../pkgs/bkt { };

  # Safe fallbacks for channels that don't have the latest attributes yet.
  nodejsPkg =
    if pkgs ? nodejs_24 then
      pkgs.nodejs_24
    else if pkgs ? nodejs_22 then
      pkgs.nodejs_22
    else
      pkgs.nodejs;

  pythonPkg =
    if pkgs ? python315 then
      pkgs.python315
    else if pkgs ? python314 then
      pkgs.python314
    else if pkgs ? python313 then
      pkgs.python313
    else
      pkgs.python3;

  basePkgs =
    with pkgs;
    [
      # Core tooling
      git
      gnupg
      vim-full
      wget
      tmux
      curl
      dnsutils
      ripgrep
      fd
      jq
      atuin
      unzip
      zip
      tree
      file
      rsync
      openssh
      bash
      coreutils
      gawk
      gnused
      ed
      fzf
      zoxide
      age
      zx
      figlet
      tiny
      weechat
      pkgs-unstable.fastfetch
      inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
      pkgs-unstable.yazi
      eza
      gh
      bkt

      # Nice to have
      pkgs-unstable.yt-dlp
      radare2

      # Cloud CLIs
      awscli2
      terraform

      # Languages that come with global packages
      nodejsPkg
      pythonPkg
      dotnetCorePackages.sdk_9_0
      # pipx 1.8.0 in 26.05 fails its own test_package_specifier suite (upstream
      # `packaging` normalization changed `name @ url` spacing; tests not updated).
      # Skip the package's checks until nixpkgs catches up.
      (pipx.overridePythonAttrs (_: {
        doCheck = false;
        doInstallCheck = false;
      }))
      deno
      go
      gcc
      rustup
      nixd
      nil

      # Per-directory dev toolchain switching
      direnv
      nix-direnv

      # AI Agents
      pkgs-unstable.claude-code
      claude-monitor
    ]
    ++ lib.optional (
      inputs.upf.packages ? ${pkgs.stdenv.hostPlatform.system}
    ) inputs.upf.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  /*
    Base Home Manager package set (CLI / portable)

    Intent:
    - Keep this list as cross-platform and headless-friendly as possible.
    - Avoid GUI apps here; those belong in `packages/desktop.nix`.
    - This module only adds packages; it does not configure their programs.

    Implementation note:
    - Do not self-reference `config.my.home.base.packages` here; that can create
      infinite recursion when Home Manager evaluates `home.packages = cfg.packages`.
    - Use `lib.mkAfter` to append to the option definition instead.
  */

  config = lib.mkIf baseEnabled {
    my.home.base.packages = lib.mkAfter basePkgs;
  };
}
