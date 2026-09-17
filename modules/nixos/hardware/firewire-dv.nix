{ lib, config, pkgs, ... }:

let
  cfg = config.my.hardware.firewireDv;
in
{
  options.my.hardware.firewireDv = {
    enable = lib.mkEnableOption "FireWire (IEEE 1394) DV capture for MiniDV camcorders";
  };

  config = lib.mkIf cfg.enable {
    # firewire-ohci normally autoloads off the PCI ID when the card is present.
    # Naming it here is belt-and-braces, and it documents which driver is in
    # play if /dev/fw* ever fails to show up.
    boot.kernelModules = [ "firewire-ohci" ];

    # The kernel hands out /dev/fw* as root:root 0600. dvgrab opens the
    # controller node to walk the bus and then the camcorder's own node, so
    # both need to be reachable without sudo.
    #
    # uaccess covers whoever is logged in at the seat; the video group is the
    # fallback for anything outside a logind session (scripts, a detached
    # capture running under `linger`).
    services.udev.extraRules = ''
      # FireWire char devices - DV camcorder capture via dvgrab
      SUBSYSTEM=="firewire", KERNEL=="fw[0-9]*", GROUP="video", MODE="0660", TAG+="uaccess"
    '';

    environment.systemPackages = with pkgs; [
      # Captures raw DV off the tape over i.LINK. The transfer is a straight
      # copy of what's already on the tape, so there's no re-encode loss.
      dvgrab
    ];
  };
}
