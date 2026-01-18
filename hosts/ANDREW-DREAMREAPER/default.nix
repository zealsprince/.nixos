{
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:

let
  # SDDM (Login Screen) background (Breeze theme)
  #
  # SDDM runs before any user session exists, so it cannot reliably read files
  # from your home directory (e.g. /home/zealsprince/Desktop/background.jpg).
  #
  # Place `background.jpg` next to this file:
  #   `.nixos/hosts/ANDREW-DREAMREAPER/background.jpg`
  sddmBackgroundImage = pkgs.runCommand "sddm-background-image" { } ''
    cp ${./background.jpg} $out
  '';
in

{

  imports = [
    ./hardware-configuration.nix

    # Host-specific boot / platform details live here so they don't leak into
    # reusable configs or non-NixOS usage.
    ./boot.nix

    # Encrypted swap (random key each boot)
    ./swap.nix

    # Storage / mounts
    ../../modules/nixos/storage/auto-mounts.nix

    # Polkit rules (host-specific)
    ./polkit-udisks2.nix

    # Common, reusable NixOS modules (kept host-agnostic)
    ../../modules/nixos/common.nix
    ../../modules/nixos/desktop/plasma6.nix
    ../../modules/nixos/programs/1password.nix
    ../../modules/nixos/security/howdy.nix
    ../../modules/nixos/services.nix

    # Hardware permissions (FlexBar USB access)
    ../../modules/nixos/hardware/flexbar.nix
    ../../modules/nixos/hardware/openrgb.nix

    # Base system packages for all hosts
    ../../modules/nixos/packages/base.nix

    # Desktop package sets:
    # - `desktop.nix` is DE-agnostic GUI apps (safe for Hyprland, etc.)
    # - `desktop.plasma.nix` is Plasma/KDE-specific apps/utilities
    ../../modules/nixos/packages/desktop.nix
    ../../modules/nixos/packages/desktop.plasma.nix

    # Host-only custom (niche) packages
    ../../modules/nixos/packages/custom.nix
  ];

  # ===========================================================================
  # RAM disk (tmpfs)
  # ===========================================================================
  #
  # This creates a 2GiB tmpfs at /ramdisk.
  fileSystems."/ramdisk" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [
      "size=2G"
      "mode=1777"
      "nosuid"
      "nodev"
      "noexec"
    ];
  };

  # Ensure the mountpoint has the desired owner/group/mode after it's mounted.
  #
  # NOTE: `mode=...` in the tmpfs mount options affects the root of the tmpfs,
  # but enforcing owner/group is best done via tmpfiles.
  systemd.tmpfiles.rules = [
    "d /ramdisk 1777 zealsprince users - -"
  ];

  # Fix for broken Zed Editor tests blocking rebuilds
  nixpkgs.overlays = [
    (final: prev: {
      zed-editor = prev.zed-editor.overrideAttrs (old: {
        doCheck = false;
      });
    })
  ];

  my.services.openlinkhub.enable = true;
  my.services.opensnitch = {
    enable = true;
    monitorMethod = "proc";
  };
  my.services.mullvad.enable = true;
  my.services.ollama = {
    enable = true;
    package = pkgs-unstable.ollama-rocm;
    acceleration = "rocm";

    # RX 6800 XT (RDNA2 / gfx1030): some ROCm stacks need an explicit override.
    extraEnvironment = {
      HSA_OVERRIDE_GFX_VERSION = "10.3.0";
    };
  };

  # ===========================================================================
  # SDDM (Login Screen) background (Breeze theme)
  #
  # SDDM runs before any user session exists, so it cannot reliably read files
  # from your home directory (e.g. /home/zealsprince/Desktop/background.jpg).
  #
  # This installs a `theme.conf.user` override into the system profile so the
  # default Breeze theme uses your chosen background.
  #
  # Notes:
  # - Place `background.jpg` next to this file:
  #   `.nixos/hosts/ANDREW-DREAMREAPER/background.jpg`
  # - Rebuild after adding the file.
  # ===========================================================================

  # ===========================================================================
  # Host identity / networking (host-specific)
  # ===========================================================================
  networking.hostName = "ANDREW-DREAMREAPER";
  networking.networkmanager.enable = true;

  # ===========================================================================
  # Enable reusable module options for this host
  # ===========================================================================
  my.services.ckb-next.enable = true;

  # Corsair Virtuoso: set hardware sidetone at login (via ALSA amixer)
  my.services.virtuosoSidetone = {
    enable = true;
    level = 23;
  };

  my.desktop.plasma6 = {
    enable = true;
    videoDrivers = [ "amdgpu" ];
    defaultSession = "plasma";

    # Revert SDDM to X11 to avoid flickering (likely caused by Wayland VRR)
    sddm = {
      enable = true;
      wayland = false;
      forceWaylandDisplayServer = false;
    };

    xkb = {
      layout = "us";
      variant = "";
    };
  };

  my.programs._1password = {
    enable = true;
    polkitPolicyOwners = [ "zealsprince" ];
    allowedBrowsers = [
      "firefox"
      "firefox-devedition"
      "zen"
    ];
  };

  my.security.howdy = {
    enable = true;
    devicePath = "/dev/video0";
    timeout = 2;

    noConfirmation = true;
    abortIfSsh = true;

    pam = {
      enableSudo = true;
      enableKde = true;
      force = true;
    };
  };

  # ===========================================================================
  # Windows apps via WinApps-style integration (KVM/libvirt + RDP)
  # ===========================================================================
  my.virtualisation.winapps = {
    enable = true;

    # NAT-only: keep libvirt's default NAT network.
    #
    # Recommended approach: forward a host port to the VM's 3389 and point the
    # launchers at localhost. For example: 127.0.0.1:13389 -> VM:3389
    #
    # If you haven't set up a forward yet, you can temporarily point `host` at the
    # VM's NAT IP (e.g. 192.168.122.x), but that tends to change.
    host = "127.0.0.1";
    port = 13389;

    # Optional but nice: share files between Linux and Windows via RDP drive redirects.
    drives = {
      "Downloads" = "/home/zealsprince/Downloads";
      "Zeal" = "/mnt/Zeal";
    };

    # Add your Windows username here if you want. Leaving it null may prompt.
    # username = "YourWindowsUser";

    # Do NOT put passwords in Nix config (it can end up in the Nix store).
    password = null;

    apps = {
      # "Affinity Photo" = {
      #   desktopName = "Affinity Photo (Windows)";
      #   categories = [ "Graphics" ];
      #   icon = "applications-graphics";

      #   # Adjust path to match the actual Affinity install location in your VM.
      #   remoteProgram = "C:\\Program Files\\Affinity\\Photo 2\\Photo.exe";
      # };
    };
  };

  # ===========================================================================
  # Storage (host-specific automounts)
  # ===========================================================================
  # These mount on first access (systemd automount) and won't block boot.
  # Device paths here use stable /dev/disk/by-uuid identifiers.
  my.storage.autoMounts = {
    enable = true;

    # Match ownership/permissions to your primary user.
    ownerUid = 1000;
    ownerGid = 100;
    umask = "0002";

    # If a drive is unplugged/slow, don't hang anything.
    deviceTimeoutSec = 10;
    mountTimeoutSec = 30;
    idleTimeoutSec = 300;

    mounts = {
      Strike = {
        device = "/dev/disk/by-label/Strike";
        mountPoint = "/mnt/Strike";
        fsType = "ext4";
      };

      Storage = {
        device = "/dev/disk/by-label/Storage";
        mountPoint = "/mnt/Storage";
        fsType = "exfat";
      };

      Footage = {
        device = "/dev/disk/by-label/Footage";
        mountPoint = "/mnt/Footage";
        fsType = "xfs";
      };

      Zeal = {
        device = "/dev/disk/by-label/Zeal";
        mountPoint = "/mnt/Zeal";
        fsType = "exfat";
      };
    };
  };

  # ===========================================================================
  # Host-local overrides / quirks
  # ===========================================================================
  # Keep per-machine tweaks here rather than in common modules.

  # Enable nix-ld to support Zed LSPs and other downloaded binaries
  programs.nix-ld.enable = true;

  # KDE Partition Manager
  programs.partition-manager.enable = true;

  # Steam (host needs 32-bit OpenGL/Vulkan userspace for Steam + many games)
  programs.steam.enable = true;

  # OpenRGB: enable AMD SMBus driver support for this host
  hardware.openrgb.motherboard = "amd";

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
      rocmPackages.hiprt
    ];
  };

  environment.systemPackages = with pkgs; [
    rocmPackages.rocminfo

    # Printing/scanning utilities
    system-config-printer
    cups-filters

    # SDDM (Login Screen) background override for Breeze theme.
    (pkgs.writeTextDir "share/sddm/themes/breeze/theme.conf.user" ''
      [General]
      background = "${sddmBackgroundImage}"
    '')
  ];

  # Ensure the user exists on this host (can be moved to a reusable "profile"
  # module later if multi-user support is needed).
  users.users.zealsprince = {
    isNormalUser = true;
    description = "Andrew Lake";

    # libvirt: manage VMs from virt-manager without sudo
    extraGroups = [
      "networkmanager"
      "wheel"
      "video"
      "plugdev"
      "libvirtd"
      "scanner"
      "lp"
    ];

    shell = pkgs.zsh;
  };

  # ===========================================================================
  # Docker (rootless)
  # ===========================================================================
  virtualisation.docker = {
    # Disable the system-wide Docker daemon (rootful).
    enable = false;

    # Run Docker as a per-user service instead.
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };

  # Keep user services running after logout so rootless Docker containers persist.
  users.users.zealsprince.linger = true;

  # ===========================================================================
  # Bluetooth
  # ===========================================================================
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      Policy = {
        # Enable all controllers when they are found. This includes
        # adapters present on start as well as adapters that are plugged
        # in later on. Defaults to 'true'.
        AutoEnable = true;
      };
    };
  };

  services.blueman.enable = true;

  # ===========================================================================
  # Scanning (SANE) + Printing (CUPS) + network discovery ("Scan to PC")
  # ===========================================================================
  #
  # Notes:
  # - Scanning apps (Simple Scan, Skanlite, etc.) use SANE.
  # - Many modern network scanners use eSCL (AirScan) and/or WSD discovery.
  # - Printing is via CUPS; driver coverage is handled via gutenprint + vendor
  #   drivers where available (Epson).
  # - Avahi (mDNS/Bonjour) helps printers/scanners show up automatically on LAN.
  #
  # If you have a USB device, the relevant udev permissions are handled by the
  # `scanner` and `lp` groups below.
  hardware.sane.enable = true;

  # Recommended backends:
  # - `sane-airscan` for eSCL/AirScan network scanners (common for "scan to PC").
  # - `hplipWithPlugin` is useful for many HP devices (optional but often needed).
  hardware.sane.extraBackends = with pkgs; [
    sane-airscan
    hplipWithPlugin
  ];

  # Printing (CUPS)
  services.printing = {
    enable = true;

    # Broad driver coverage:
    # - gutenprint: large set of PPDs for many inkjets/lasers (incl. many Epson)
    # - epson-escpr / epson-escpr2: Epson's ESC/P-R driver(s) for many models
    drivers = with pkgs; [
      gutenprint
      epson-escpr
      epson-escpr2
    ];
  };

  # Optional but commonly needed GUI and tools (especially on KDE/Plasma) are
  # included in the existing `environment.systemPackages` list above.

  # Make sure your user can access scanners/printers.
  # (Handled in the primary `users.users.zealsprince.extraGroups` definition above.)

  # mDNS discovery for network printers/scanners (AirPrint/AirScan style)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # If your host firewall is enabled, allow common discovery/scan-to-PC ports.
  networking.firewall.allowedTCPPorts = [
    5357 # WSD (Web Services on Devices)
    8612 # eSCL (AirScan) - common
  ];

  # UDP 5353 is mDNS (Avahi); handled via `services.avahi.openFirewall = true`.

  # ===========================================================================
  # Corsair Virtuoso - permissions + auto-apply sidetone on device arrival
  # ===========================================================================
  # - HeadsetControl talks to the headset via /dev/hidraw*; opening needs permissions.
  # - Virtuoso sidetone is exposed via ALSA ("Sidetone" mixer control).
  #   We want sidetone to be re-applied every time the device shows up (USB add/change).
  services.udev.extraRules = lib.mkAfter ''
    # Corsair Virtuoso Wireless (dongle mode): allow non-root hidraw access
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1b1c", ATTRS{idProduct}=="0a42", MODE="0660", GROUP="plugdev"
    # Corsair Virtuoso USB (wired mode): allow non-root hidraw access
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1b1c", ATTRS{idProduct}=="0a49", MODE="0660", GROUP="plugdev"

    # Trigger sidetone apply whenever the Virtuoso USB device appears.
    # (We match both dongle and wired modes.)
    ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="1b1c", ATTR{idProduct}=="0a42", TAG+="systemd", ENV{SYSTEMD_WANTS}+="virtuoso-sidetone.service"
    ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="1b1c", ATTR{idProduct}=="0a49", TAG+="systemd", ENV{SYSTEMD_WANTS}+="virtuoso-sidetone.service"
  '';

  # Keep state version pinned per-host.
  system.stateVersion = "25.11";
}
