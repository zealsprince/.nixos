{ config, lib, ... }:

let
  cfg = config.my.programs._1password;
in
{
  options.my.programs._1password = {
    enable = lib.mkEnableOption "1Password integration (GUI + optional browser allowlist)";

    polkitPolicyOwners = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "zealsprince" ];
      description = "Users allowed to authorize 1Password polkit actions.";
    };

    allowedBrowsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "firefox"
        "firefox-devedition"
        "zen"
      ];
      description = ''
        Lines written to `/etc/1password/custom_allowed_browsers`.

        Set this when browser integration is used and non-default browser
        binaries must be allowed (e.g. Zen Browser).
      '';
    };

    enableShellPluginsModule = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable the upstream 1Password shell-plugins NixOS module.

        Note: this module does not import that upstream module. Enable it
        elsewhere (e.g. in the flake module list), then set this option so the
        remaining configuration can assume it is present.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs._1password.enable = true;

    programs._1password-gui = {
      enable = true;
      polkitPolicyOwners = cfg.polkitPolicyOwners;
    };

    environment.etc = lib.mkIf (cfg.allowedBrowsers != [ ]) {
      "1password/custom_allowed_browsers" = {
        text = lib.concatStringsSep "\n" cfg.allowedBrowsers + "\n";
        mode = "0755";
      };
    };
  };
}
