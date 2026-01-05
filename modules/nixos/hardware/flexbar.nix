{ config, lib, pkgs, ... }:

/*
  FlexBar USB permissions (ENIAC-Tech FlexBar)

  FlexDesigner recommends udev rules like:

    SUBSYSTEM=="usb",     ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bd", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="hidraw",  ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bd", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb",     ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bf", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="tty",     ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bf", MODE="0666", GROUP="plugdev"

  This module implements that in a NixOS-native way, plus ensures the `plugdev`
  group exists.

  Usage (import this module from a host that needs it):
    imports = [
      ../../modules/nixos/hardware/flexbar.nix
    ];

  Then add your user to the `plugdev` group on that host:
    users.users.<name>.extraGroups = [ "plugdev" ... ];
*/

{
  # Ensure the group mentioned by the upstream udev rules exists.
  users.groups.plugdev = { };

  services.udev.extraRules = ''
    # FlexBar (ENIAC-Tech) — allow non-root access via plugdev group
    SUBSYSTEM=="usb",    ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bd", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bd", MODE="0666", GROUP="plugdev"

    SUBSYSTEM=="usb",    ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bf", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="tty",    ATTRS{idVendor}=="303a", ATTRS{idProduct}=="82bf", MODE="0666", GROUP="plugdev"
  '';
}
