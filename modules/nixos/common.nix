{ config, lib, pkgs, ... }:

{
  # Allow explicitly permitted insecure deps required by some packages (e.g. teamspeak3).
  nixpkgs.config.permittedInsecurePackages = lib.mkDefault [
    "qtwebengine-5.15.19"
  ];
  # ===========================================================================
  # Common, reusable NixOS settings
  #
  # Intended to be importable across hosts without carrying host-specific
  # assumptions (disk layout, secure boot, hardware IDs, etc.).
  # ===========================================================================

  # Networking baseline (hostName belongs in hosts/<name>/default.nix)
  networking.networkmanager.enable = lib.mkDefault true;

  # Locale / time (can be overridden per-host)
  time.timeZone = lib.mkDefault "America/Edmonton";

  i18n.defaultLocale = lib.mkDefault "en_CA.UTF-8";
  i18n.extraLocaleSettings = lib.mkDefault {
    LC_ADDRESS = "en_CA.UTF-8";
    LC_IDENTIFICATION = "en_CA.UTF-8";
    LC_MEASUREMENT = "en_CA.UTF-8";
    LC_MONETARY = "en_CA.UTF-8";
    LC_NUMERIC = "en_CA.UTF-8";
    LC_PAPER = "en_CA.UTF-8";
    LC_TELEPHONE = "en_CA.UTF-8";
    LC_TIME = "en_CA.UTF-8";
  };

  # Editor defaults
  #
  # Set defaults at the option level to avoid conflicts with other modules that
  # define `environment.variables` (e.g. defaults to nano). Individual keys using
  # `mkDefault` can still conflict when multiple defaults exist.
  environment.variables = lib.mkDefault {
    EDITOR = "vim";
    VISUAL = "vim";
  };

  # Allow unfree packages by default for this configuration
  nixpkgs.config.allowUnfree = lib.mkDefault true;

  # Nix settings
  nix.settings = {
    experimental-features = lib.mkDefault [ "nix-command" "flakes" ];
    substituters = lib.mkDefault [ "https://nix-community.cachix.org" ];
    trusted-public-keys = lib.mkDefault [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    auto-optimise-store = lib.mkDefault true;
  };

  # GC defaults
  nix.gc = lib.mkDefault {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # Shell baseline
  #
  # Avoid setting `users.defaultUserShell` globally here because NixOS defines a
  # default (bash) and this can conflict during module evaluation. Enable zsh,
  # and set the default shell per-user or in a host/profile module when needed.
  programs.zsh.enable = lib.mkDefault true;

  # Convenience
  programs.firefox.enable = lib.mkDefault false; # example: overridden when using Zen
}
