{ lib, pkgs, ... }:

let
  # The physical partition to use (referenced by PARTUUID since UUID is wiped on format)
  swapPartUuid = "14a5934b-1feb-414a-8b03-cdd668a99ec4";
  rawDevice = "/dev/disk/by-partuuid/${swapPartUuid}";

  # The mapped device name
  cryptName = "cryptswap";
  mappedDevice = "/dev/mapper/${cryptName}";
in
{
  # --------------------------------------------------------------------------------
  # 1. Clean Slate
  # --------------------------------------------------------------------------------
  # Disable all declarative swap devices to prevent NixOS generating .swap units
  # or fstab entries that might conflict or create dependency cycles.
  swapDevices = lib.mkForce [ ];

  # Ensure no crypttab entries exist (removes generated units entirely).
  environment.etc."crypttab".text = lib.mkForce "";

  # Prevent systemd-gpt-auto-generator from automatically finding and activating
  # the raw swap partition (which causes "device busy" errors).
  boot.kernelParams = [ "systemd.gpt_auto=0" ];

  # Tell UDisks2 (and thus Dolphin) to ignore this partition.
  services.udev.extraRules = ''
    ENV{ID_PART_ENTRY_UUID}=="${swapPartUuid}", ENV{UDISKS_IGNORE}="1"
  '';

  # --------------------------------------------------------------------------------
  # 2. Monolithic Service
  # --------------------------------------------------------------------------------
  # This service handles the entire lifecycle: Open -> Format -> Swapon
  #
  # CHANGES VS PREVIOUS:
  # - DefaultDependencies = "no": Prevents cycles with sysinit.target.
  # - Aggressive cleanup: Always closes/wipes old mapping on start to ensure
  #   we don't get stuck with a stale, unformatted mapper.
  # --------------------------------------------------------------------------------
  systemd.services.ephemeral-encrypted-swap = {
    description = "Ephemeral Encrypted Swap (Random Key)";

    # Start this unit when swap.target is requested
    wantedBy = [ "swap.target" ];

    # Ensure we run before swap.target tells the system "swap is ready"
    before = [ "swap.target" ];

    # Ensure we stop before systemd-udevd (by starting after it), so cryptsetup
    # can communicate with udevd during teardown.
    after = [ "systemd-udevd.service" ];

    # Conflict with shutdown to ensure clean teardown
    conflicts = [ "shutdown.target" ];

    # We need the device node to exist
    unitConfig = {
      RequiresMountsFor = rawDevice;
      # Crucial to avoid dependency cycles with basic system initialization
      DefaultDependencies = "no";
    };

    # Required tools
    path = [
      pkgs.cryptsetup
      pkgs.util-linux
      pkgs.lvm2
      pkgs.coreutils
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStopSec = "500ms";

      # Startup: Clean -> Open -> Format -> Enable
      ExecStart = pkgs.writeShellScript "enable-cryptswap" ''
        set -euo pipefail

        # 0. Safety cleanup: if the mapper exists from a failed run or previous boot,
        #    tear it down so we start fresh.
        if [ -e "${mappedDevice}" ]; then
          echo "Cleaning up stale device ${mappedDevice}..."
          swapoff "${mappedDevice}" || true
          cryptsetup close "${cryptName}" || true
        fi

        # 1. Generate ephemeral key
        keyfile="/run/cryptswap.key"
        umask 077
        dd if=/dev/urandom of="$keyfile" bs=64 count=1 status=none

        # 2. Format as LUKS2 (so fwupd sees it as encrypted) and Open
        echo "Formatting ${rawDevice} as ephemeral LUKS2..."
        cryptsetup luksFormat --type luks2 --batch-mode \
          "${rawDevice}" "$keyfile"

        echo "Opening ${rawDevice}..."
        cryptsetup open "${rawDevice}" "${cryptName}" --key-file "$keyfile"

        # Wipe key immediately
        rm -f "$keyfile"

        # 3. Format as swap
        echo "Formatting ${mappedDevice} as swap..."
        mkswap "${mappedDevice}"

        # 4. Activate
        echo "Activating swap on ${mappedDevice}..."
        swapon "${mappedDevice}"
      '';

      # Teardown: Disable -> Close
      ExecStop = pkgs.writeShellScript "disable-cryptswap" ''
        set -uo pipefail

        if [ -e "${mappedDevice}" ]; then
          echo "Deactivating swap on ${mappedDevice}..."
          swapoff "${mappedDevice}" || true

          echo "Closing ${cryptName}..."
          cryptsetup close "${cryptName}" || true
        fi
      '';
    };
  };
}
