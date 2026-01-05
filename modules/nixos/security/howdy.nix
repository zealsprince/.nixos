{ config, lib, pkgs, inputs ? null, ... }:

let
  cfg = config.my.security.howdy;

  # Prefer the howdy package from the nixpkgs-howdy flake input when available,
  # fall back to nixpkgs' howdy otherwise.
  howdyPkg =
    if inputs != null
    && inputs ? nixpkgs-howdy
    && inputs.nixpkgs-howdy ? legacyPackages
    && inputs.nixpkgs-howdy.legacyPackages ? ${pkgs.stdenv.hostPlatform.system}
    && inputs.nixpkgs-howdy.legacyPackages.${pkgs.stdenv.hostPlatform.system} ? howdy
    then inputs.nixpkgs-howdy.legacyPackages.${pkgs.stdenv.hostPlatform.system}.howdy
    else pkgs.howdy;
in
{
  options.my.security.howdy = {
    enable = lib.mkEnableOption "Howdy face authentication (with opinionated PAM integration)";

    devicePath = lib.mkOption {
      type = lib.types.str;
      default = "/dev/video0";
      description = "Camera device path used by Howdy.";
      example = "/dev/video2";
    };

    timeout = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Howdy face scan timeout in seconds.";
      example = 5;
    };

    noConfirmation = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to skip confirmation prompts after a successful face match.";
    };

    abortIfSsh = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether Howdy auth should be skipped/aborted for SSH sessions.";
    };

    pam = {
      enableSudo = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Inject Howdy into the sudo PAM stack (face -> password fallback).";
      };

      enableKde = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Inject Howdy into KDE lock screen PAM stack (face -> password fallback).";
      };

      force = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Force-override PAM service definitions for enabled PAM targets.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.howdy = {
      enable = true;
      package = howdyPkg;
      settings = {
        core = {
          no_confirmation = cfg.noConfirmation;
          abort_if_ssh = cfg.abortIfSsh;
        };
        video = {
          device_path = cfg.devicePath;
          timeout = cfg.timeout;
        };
      };
    };

    # -------------------------------------------------------------------------
    # PAM integration (opinionated / reusable)
    # -------------------------------------------------------------------------
    # Notes:
    # - The intent is: try Howdy first; if it fails, fall back to password.
    # - If `pam.force = true`, we use mkForce to fully replace service text.
    # - KDE includes optional kwallet PAM integration.
    security.pam.services.sudo.text =
      lib.mkIf cfg.pam.enableSudo (
        (if cfg.pam.force then lib.mkForce else lib.mkDefault) ''
          # -----------------------------------------------------------------------
          # 1. Authentication (Check Face -> Then Password)
          # -----------------------------------------------------------------------
          # FACE: Check Howdy First. If success, return immediately.
          auth sufficient ${config.services.howdy.package}/lib/security/pam_howdy.so

          # PASSWORD: Original system logic (pam_unix)
          # 'try_first_pass' allows it to catch the password if Howdy prompted for one.
          auth sufficient pam_unix.so likeauth try_first_pass

          # If both fail, deny access.
          auth required pam_deny.so

          # -----------------------------------------------------------------------
          # 2. Account Management (CRITICAL)
          # -----------------------------------------------------------------------
          account required pam_unix.so

          # -----------------------------------------------------------------------
          # 3. Password Management (For passwd command, etc)
          # -----------------------------------------------------------------------
          password sufficient pam_unix.so nullok yescrypt

          # -----------------------------------------------------------------------
          # 4. Session Management
          # -----------------------------------------------------------------------
          session required pam_env.so conffile=/etc/pam/environment readenv=0
          session required pam_unix.so
          session required pam_limits.so
        ''
      );

    security.pam.services.kde.text =
      lib.mkIf cfg.pam.enableKde (
        (if cfg.pam.force then lib.mkForce else lib.mkDefault) ''
          # -----------------------------------------------------------------------
          # 1. Check Face (Howdy)
          # -----------------------------------------------------------------------
          auth     sufficient     ${config.services.howdy.package}/lib/security/pam_howdy.so

          # -----------------------------------------------------------------------
          # 2. Authentication (Original System Defaults)
          # -----------------------------------------------------------------------
          # Try to unlock KWallet early (optional)
          auth     optional       ${pkgs.kdePackages.kwallet-pam}/lib/security/pam_kwallet5.so

          # Check Password (pam_unix)
          auth     sufficient     pam_unix.so try_first_pass likeauth nullok

          # If everything failed, deny access
          auth     required       pam_deny.so

          # -----------------------------------------------------------------------
          # 3. Account & Session Management (Original System Defaults)
          # -----------------------------------------------------------------------
          account  required       pam_unix.so

          # Setup environment (Path, Variables, etc)
          session  required       pam_env.so conffile=/etc/pam/environment readenv=0
          session  required       pam_unix.so

          # Unlock KWallet session
          session  optional       ${pkgs.kdePackages.kwallet-pam}/lib/security/pam_kwallet5.so
        ''
      );
  };
}
