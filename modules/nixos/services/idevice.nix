{ lib, config, pkgs, ... }:

let
  cfg = config.my.services.idevice;
in
{
  options.my.services.idevice = {
    enable = lib.mkEnableOption "iPhone/iPad USB support (usbmuxd, libimobiledevice, ifuse)";
  };

  config = lib.mkIf cfg.enable {
    # usbmuxd is the daemon that multiplexes USB connections to Apple devices.
    # Everything else rides on it: Dolphin's afc:// view (via kio-extras),
    # the idevice* CLI tools, and USB tethering authentication.
    services.usbmuxd.enable = true;

    environment.systemPackages = with pkgs; [
      libimobiledevice # CLI: idevicepair, ideviceinfo, idevicebackup2
      ifuse # FUSE mount for the media / app file-sharing view
    ];
  };
}
