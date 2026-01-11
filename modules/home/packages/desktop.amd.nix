{ config, pkgs, lib, ... }:

let
  cfg = config.my.home.packages.desktop.amd;
in
{
  options.my.home.packages.desktop.amd = {
    enable = lib.mkEnableOption "AMD GPU-specific desktop (GUI) user package set for Home Manager";

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = ''
        Extra AMD-specific desktop packages to add on top of the default desktop set.

        Keep this module scoped to AMD GPU-specific tooling. Prefer putting
        desktop-neutral GUI apps in `my.home.packages.desktop`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      (with pkgs; [

      ])
      ++ cfg.packages;
  };
}
