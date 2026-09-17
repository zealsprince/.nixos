{ lib, config, ... }:

/*
  FlexBar USB permissions (ENIAC-Tech FlexBar)

  FlexDesigner recommends udev rules like:

    SUBSYSTEM=="usb",     ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bd", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="hidraw",  ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bd", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb",     ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bf", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="tty",     ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bf", MODE="0666", GROUP="plugdev"

  This module implements that in a NixOS-native way.

  The `plugdev` group itself is declared in modules/nixos/common.nix, since the
  Virtuoso rules and my user account both depend on it independently of whether
  the FlexBar is enabled here.

  Usage:
    my.hardware.flexbar.enable = true;

  Then add the user to the `plugdev` group on that host:
    users.users.<name>.extraGroups = [ "plugdev" ... ];
*/

let
  cfg = config.my.hardware.flexbar;
in
{
  options.my.hardware.flexbar = {
    enable = lib.mkEnableOption "FlexBar (ENIAC-Tech) USB permissions";
  };

  config = lib.mkIf cfg.enable {
    services.udev.extraRules = ''
      # FlexBar (ENIAC-Tech): allow non-root access via plugdev group
      SUBSYSTEM=="usb",    ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bd", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bd", MODE="0666", GROUP="plugdev"

      SUBSYSTEM=="usb",    ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bf", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="tty",    ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bf", MODE="0666", GROUP="plugdev"
    '';
  };
}
