{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix

    # Host-specific boot / platform details live here so they don't leak into
    # reusable configs or non-NixOS usage.
    ./boot.nix

    # Storage / mounts
    ../../modules/nixos/storage/ntfs-mounts.nix

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

  my.services.openlinkhub.enable = true;
  my.services.opensnitch.enable = true;
  my.services.mullvad.enable = true;

  # ===========================================================================
  # Host identity / networking (host-specific)
  # ===========================================================================
  networking.hostName = "ANDREW-DREAMREAPER";
  networking.networkmanager.enable = true;

  # ===========================================================================
  # Enable reusable module options for this host
  # ===========================================================================
  my.services.ckb-next.enable = true;

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
    allowedBrowsers = [ "firefox" "zen" ];
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
  # Storage (host-specific NTFS automounts)
  # ===========================================================================
  # These mount on first access (systemd automount) and won't block boot.
  # Device paths here use stable /dev/disk/by-uuid identifiers.
  my.storage.ntfsMounts = {
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
        driver = "ntfs3";
      };

      Storage = {
        device = "/dev/disk/by-label/Storage";
        mountPoint = "/mnt/Storage";
        driver = "ntfs3";
      };

      Recording = {
        device = "/dev/disk/by-label/Recording";
        mountPoint = "/mnt/Recording";
        driver = "ntfs3";
      };

      Zeal = {
        device = "/dev/disk/by-label/Zeal";
        mountPoint = "/mnt/Zeal";
        driver = "ntfs3";
      };
    };
  };

  # ===========================================================================
  # Host-local overrides / quirks
  # ===========================================================================
  # Keep per-machine tweaks here rather than in common modules.

  # Steam (host needs 32-bit OpenGL/Vulkan userspace for Steam + many games)
  programs.steam.enable = true;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Ensure the user exists on this host (can be moved to a reusable "profile"
  # module later if multi-user support is needed).
  users.users.zealsprince = {
    isNormalUser = true;
    description = "Andrew Lake";

    # libvirt: manage VMs from virt-manager without sudo
    extraGroups = [ "networkmanager" "wheel" "video" "plugdev" "libvirtd" ];

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
  };

  services.blueman.enable = true;

  # Keep state version pinned per-host.
  system.stateVersion = "25.11";
}
