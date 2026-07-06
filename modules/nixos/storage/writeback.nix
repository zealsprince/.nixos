{ pkgs, lib, ... }:

{
  # ==========================================================================
  # Honest write buffering
  # ==========================================================================
  #
  # By default the kernel caps dirty (unwritten) page cache as a percentage of
  # RAM: vm.dirty_ratio = 20%. With 128GB of RAM that is ~25GB of data that
  # `cp`/`rsync` can "finish" writing while it still sits in memory. Progress
  # bars lie, unmounting a slow USB drive then blocks for many minutes while
  # the real writeback happens, and pulling the drive early loses data.
  #
  # Fix in two layers:
  #
  # 1. Global absolute cap (applies to every device, including disk-to-disk
  #    copies): at most 256MB of dirty data system-wide. An NVMe drains that
  #    in a fraction of a second, so there is no practical throughput cost,
  #    but no copy can ever appear more than 256MB ahead of the actual disk.
  #
  # 2. Per-device strict limit for USB storage: each USB disk gets its own
  #    64MB writeback window (kernel >= 6.2 exposes this via bdi/max_bytes).
  #    Writes stay async and full speed, the kernel just refuses to buffer
  #    gigabytes for a 20MB/s stick. Unmount completes in about a second.
  boot.kernel.sysctl = {
    # Setting *_bytes overrides the *_ratio percentage equivalents.
    "vm.dirty_bytes" = 268435456; # 256MB hard cap, writers block above this
    "vm.dirty_background_bytes" = 67108864; # 64MB, background flush starts here
  };

  services.udev.extraRules = lib.mkAfter ''
    # Cap per-device write buffering for USB storage so copy progress and
    # unmount times reflect the real device speed. DEVTYPE=="disk" because
    # the bdi/ sysfs node lives on the whole disk, not partitions.
    ACTION=="add|change", SUBSYSTEM=="block", SUBSYSTEMS=="usb", ENV{DEVTYPE}=="disk", \
      RUN+="${pkgs.runtimeShell} -c 'echo 1 > /sys%p/bdi/strict_limit; echo 67108864 > /sys%p/bdi/max_bytes'"
  '';
}
