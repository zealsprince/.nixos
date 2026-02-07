{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  inputs,
  ...
}:

let
  # We piggy-back on your existing "base HM profile" toggle so this module is a
  # "thing on top" of the user-level base configuration, not the system config.
  baseEnabled = config.my.home.base.enable or false;

  basePkgs = with pkgs; [
    inputs.agenix.packages.${pkgs.system}.default
    eza
    gh
    pkgs-unstable.yt-dlp
    awscli2
    terraform
    radare2

    # Languages that come with global packages
    nodejs_24
    python315
    pipx
    deno
    rustup
    nixd
    nil

    # Per-directory dev toolchain switching
    direnv
    nix-direnv
  ];
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
