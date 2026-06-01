{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.security.howdy;

  # Howdy is provided by nixpkgs upstream as of 26.05.
  howdyPkg = pkgs.howdy;
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

      enableHyprlock = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Inject Howdy into the hyprlock PAM stack (face -> password fallback).";
      };

      enableSwaylock = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Inject Howdy into the swaylock PAM stack (face -> password fallback).";
      };

      force = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Force-override PAM service definitions for enabled PAM targets.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # As of 26.05 the upstream `services.howdy` module auto-injects pam_howdy
    # into EVERY PAM stack (polkit-1, sddm, login, hyprlock, ...) via
    # `security.pam.howdy.enable` (which defaults to `services.howdy.enable`).
    # We do NOT want that: the KDE polkit agent speaks a strict line protocol
    # to polkit-agent-helper-1 and cannot parse pam_howdy's info messages
    # ("Howdy could not find a camera device..."), nor can pam_howdy reach the
    # camera inside polkit's sandboxed helper. The result is an instant
    # "Authentication failure" with no password fallback. We only want Howdy in
    # the sudo/kde stacks we define explicitly below, so disable the global
    # auto-injection and keep the hand-rolled stacks as the single source.
    security.pam.howdy.enable = false;

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
    security.pam.services.sudo.text = lib.mkIf cfg.pam.enableSudo (
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

    security.pam.services.kde.text = lib.mkIf cfg.pam.enableKde (
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

    # -------------------------------------------------------------------------
    # Wayland lock screens (hyprlock / swaylock)
    # -------------------------------------------------------------------------
    # These default stacks are plain pam_unix, so instead of hand-rolling raw
    # `.text` (which risks dropping the correctly-pathed pam_unix/pam_limits
    # lines) we re-enable the upstream per-service Howdy injection just for
    # these services. The rules engine inserts pam_howdy at the right order and
    # keeps everything else intact. `sufficient` => face -> password fallback.
    security.pam.services.hyprlock.howdy = lib.mkIf cfg.pam.enableHyprlock {
      enable = true;
      control = "sufficient";
    };

    security.pam.services.swaylock.howdy = lib.mkIf cfg.pam.enableSwaylock {
      enable = true;
      control = "sufficient";
    };
  };
}
