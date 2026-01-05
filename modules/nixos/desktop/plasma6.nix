{ config, lib, pkgs, ... }:

let
  cfg = config.my.desktop.plasma6;
in
{
  options.my.desktop.plasma6 = {
    enable = lib.mkEnableOption "Plasma 6 desktop (SDDM + Wayland default)";

    videoDrivers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "amdgpu" ];
      description = "Xorg video drivers to configure via services.xserver.videoDrivers.";
    };

    defaultSession = lib.mkOption {
      type = lib.types.str;
      default = "plasma";
      description = "Default display manager session name.";
    };

    sddm = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable SDDM as the display manager.";
      };

      wayland = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable SDDM Wayland support.";
      };

      forceWaylandDisplayServer = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Force SDDM to use Wayland as its display server.";
      };
    };

    xkb = {
      layout = lib.mkOption {
        type = lib.types.str;
        default = "us";
        description = "XKB keyboard layout.";
      };

      variant = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "XKB keyboard variant.";
      };
    };

    printing = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable CUPS printing.";
    };

    pipewire = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable PipeWire (with ALSA + PulseAudio compatibility).";
    };

    rtkit = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable RTKit (recommended for PipeWire).";
    };

    enableX11 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable X11 support for Plasma.";
    };
  };

  config = lib.mkIf cfg.enable {
    # ---- Desktop session ----
    services.xserver.enable = cfg.enableX11;

    # This is still used by some things even when running Wayland.
    services.xserver.videoDrivers = lib.mkIf (cfg.videoDrivers != [ ]) cfg.videoDrivers;

    services.displayManager = {
      defaultSession = cfg.defaultSession;

      sddm.enable = cfg.sddm.enable;
      sddm.wayland.enable = cfg.sddm.wayland;

      # Keep a consistent default: make SDDM use Wayland by default.
      sddm.settings = lib.mkIf cfg.sddm.forceWaylandDisplayServer {
        General.DisplayServer = "wayland";
      };
    };

    services.desktopManager.plasma6.enable = true;

    services.xserver.xkb = {
      layout = cfg.xkb.layout;
      variant = cfg.xkb.variant;
    };

    # ---- Printing ----
    services.printing.enable = cfg.printing;

    # ---- Audio ----
    security.rtkit.enable = cfg.rtkit;

    # Keep PulseAudio disabled when PipeWire is enabled (PulseAudio compatibility is provided by PipeWire).
    services.pulseaudio.enable = lib.mkIf cfg.pipewire false;

    services.pipewire = lib.mkIf cfg.pipewire {
      enable = true;

      # PipeWire routing/graph + policies
      wireplumber.enable = true;

      # ALSA + PulseAudio compatibility (your apps still “think” PulseAudio exists)
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;

      # Low-latency defaults (helps mic-monitoring / sidetone).
      #
      # Notes:
      # - Lower quantum = lower latency, but more risk of crackles.
      # - If you get crackling/robotic audio, raise these (e.g. min=128, default=256).
      # - Wireless USB dongles may still have an irreducible hardware latency floor.
      extraConfig.pipewire."92-low-latency" = {
        "context.properties" = {
          # Target sample rate for the graph
          "default.clock.rate" = 48000;

          # Quantum (buffer size) in frames
          "default.clock.quantum" = 128;
          "default.clock.min-quantum" = 64;
          "default.clock.max-quantum" = 256;
        };
      };

      # Also apply to pipewire-pulse clients (some apps behave better when pulse
      # uses the same timing constraints).
      extraConfig.pipewire-pulse."92-low-latency" = {
        "context.properties" = {
          "default.clock.rate" = 48000;
          "default.clock.quantum" = 128;
          "default.clock.min-quantum" = 64;
          "default.clock.max-quantum" = 256;
        };
      };
    };
  };
}
