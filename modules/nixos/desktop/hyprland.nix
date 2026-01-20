{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.desktop.hyprland;
in
{
  options.my.desktop.hyprland = {
    enable = lib.mkEnableOption "Hyprland desktop (wlroots compositor) with SDDM session support";

    /*
      Select which Hyprland package to use.

      Default is the stable channel (`pkgs.hyprland`), but you can switch to
      unstable per-host like:

        my.desktop.hyprland.package = pkgs-unstable.hyprland;

      (Your flake already passes `pkgs-unstable` into modules via `specialArgs`.)
    */
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.hyprland;
      description = "Hyprland package to use for programs.hyprland.package.";
    };

    /*
      Session name used by display managers.

      Notes:
      - Hyprland provides a Wayland session called "hyprland" on NixOS when enabled.
      - You typically do NOT need to set this unless you want to make Hyprland the default session.
    */
    sessionName = lib.mkOption {
      type = lib.types.str;
      default = "hyprland";
      description = "Display manager session name for Hyprland.";
    };

    /*
      SDDM integration.

      Important:
      - You already manage SDDM via `my.desktop.plasma6`. This block is intentionally
        conservative to avoid fighting Plasma’s module.
      - If SDDM is enabled elsewhere, Hyprland will still show up as a session.
    */
    sddm = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable SDDM as the display manager (only set true if no other module enables it).";
      };

      wayland = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable SDDM Wayland support (sddm.wayland.enable).";
      };

      forceWaylandDisplayServer = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Force SDDM itself to run on Wayland (General.DisplayServer = wayland).";
      };
    };

    /*
      XDG portals (recommended for wlroots/Hyprland):
      - File pickers
      - Screensharing (PipeWire)
      - “Open with…” and other desktop integration

      `xdg-desktop-portal-hyprland` is Hyprland’s portal backend.
      Having `xdg.portal.enable = true` ensures the service is available.
    */
    portals = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable XDG desktop portals suitable for Hyprland.";
      };

      extraPortals = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Additional portal backends to install (in addition to the Hyprland portal backend).";
      };
    };

    /*
      Convenience toggle for common Hyprland runtime expectations.
      Keep this minimal; actual Hyprland config belongs in Home Manager.
    */
    enableXwayland = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable XWayland support for running X11 apps under Hyprland.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Hyprland itself (+ session .desktop registration on NixOS).
    programs.hyprland = {
      enable = true;
      package = cfg.package;
      xwayland.enable = cfg.enableXwayland;
    };

    # If you want this host to boot into Hyprland by default (optional),
    # you can set:
    #   services.displayManager.defaultSession = cfg.sessionName;
    #
    # This module intentionally does NOT set it automatically.

    # Optional SDDM enabling if you want this module to manage it.
    services.displayManager = lib.mkIf cfg.sddm.enable {
      sddm.enable = true;
      sddm.wayland.enable = cfg.sddm.wayland;

      sddm.settings = lib.mkIf cfg.sddm.forceWaylandDisplayServer {
        General.DisplayServer = "wayland";
      };
    };

    # Portals: make Hyprland usable with modern desktop integrations (esp. screen share).
    #
    # Important:
    # - When `programs.hyprland.enable = true`, NixOS can manage the Hyprland portal
    #   backend automatically. Adding `xdg-desktop-portal-hyprland` here as well can
    #   lead to duplicate user unit symlinks during build.
    #
    # Notes:
    # - You can still add extra portal backends (e.g. `xdg-desktop-portal-gtk`) via
    #   `portals.extraPortals`.
    xdg.portal = lib.mkIf cfg.portals.enable {
      enable = true;

      # Let `programs.hyprland` provide the Hyprland portal backend; only add extras.
      extraPortals = cfg.portals.extraPortals;

      # Some apps depend on a default portal config. On NixOS this is often
      # automatically reasonable; if you run into issues you can add explicit
      # config later.
    };

    # A tiny set of “safe” runtime packages that often matter for wlroots compositors.
    # (Keep this light; real desktop apps belong in your existing package modules.)
    environment.systemPackages = with pkgs; [
      # Helpful debugging tools and Wayland basics. Remove if you dislike extras.
      wayland-utils
    ];
  };
}
