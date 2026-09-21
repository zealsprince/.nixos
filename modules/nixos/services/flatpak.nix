{ config, lib, ... }:

let
  cfg = config.my.services.flatpak;
in
{
  options.my.services.flatpak = {
    enable = lib.mkEnableOption "Flatpak (system service, per-user installs)";
  };

  config = lib.mkIf cfg.enable {
    # The upstream module does the real work: the system helper, the dbus and
    # systemd packages, and the two exports paths on environment.profiles, which
    # is what puts a Flatpak's .desktop file and icon in front of the session.
    services.flatpak.enable = true;

    # Upstream asserts on this. Plasma 6 already turns portals on, but a module
    # under modules/nixos/services shouldn't quietly depend on the desktop
    # module being enabled, so set it here and let plasma6 win when it's on.
    xdg.portal.enable = lib.mkDefault true;
  };
}
