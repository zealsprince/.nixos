{ lib, pkgs, ... }:

{
  # Host-specific boot configuration for ANDREW-DREAMREAPER.
  #
  # This module intentionally contains machine- / setup-specific choices:
  # - Secure Boot via Lanzaboote (systemd-boot)
  # - UEFI variables access
  # - AMDGPU initrd module
  #
  # Keep this separate from generic configs so other hosts can avoid inheriting it.

  # Prefer latest kernel (matches prior configuration for this host).
  boot.kernelPackages = pkgs.linuxPackages;

  # UEFI
  boot.loader.efi.canTouchEfiVariables = true;

  # Lanzaboote uses systemd-boot under the hood.
  # Explicitly disable other bootloaders to avoid accidental fallback changes.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub.enable = false;

  # Secure Boot via Lanzaboote
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/etc/secureboot";
  };

  # Ensure AMD GPU module is available early (matches prior configuration for this host).
  boot.initrd.kernelModules = [ "amdgpu" ];

  # Force MODE1 reset for RDNA2 (RX 6900 XT / Navi 21).
  # On a warm reboot the BIOS does not re-POST the GPU, so amdgpu must reset it
  # during init. The auto-selected reset intermittently fails on this board,
  # leaving the display with no signal and no usable TTY. MODE1 (=2) resets all
  # IP blocks individually and is the most reliable full reset for discrete
  # RDNA2. Do NOT use BACO (=4): it triggers runtime "gfx ring timeout" loops on
  # this card. PCI (=5) is also unsuitable because the GPU shares a bridge with
  # its HDMI-audio function.
  #
  # The black-screen-on-wake thing. Happens maybe 1 in 4-5 suspends. Screen
  # stays dead, keyboard lights up but nothing responds, can't even switch VT.
  # It's the GPU firmware (SMU) not coming back on resume, then the DMA engine
  # wedges a few seconds later. Look for this in `journalctl -b -1` after a bad
  # wake:
  #   SMU: I'm not done with your previous command ...
  #   RunDcBtc failed! / Failed to setup smc hw!
  #   resume of IP block <smu> failed -62
  #   ring sdma0 timeout ... -> Fence fallback timer expired (floods forever)
  # reset_method above is useless for this, it's the resume that dies, not a
  # reset. pcie_aspm=off is the usual culprit/fix for Navi 2x SMU resume
  # timeouts. Trades a bit of idle power. Not confirmed yet, give it a week of
  # suspends. If it still hangs, rip it out and try the next thing.
  #
  # next things to try, one at a time, check the journal each time:
  #   - amdgpu.aspm=0
  #   - amdgpu.runpm=0
  #   - linuxPackages_latest (SMU resume fixes trickle in upstream)
  #   - BIOS: kill Power Supply Idle Control, global C-states, ASPM
  # when it does hang, REISUB (Alt+SysRq, r e i s u b) instead of holding power.
  boot.kernelParams = [
    "amdgpu.reset_method=2"
    "pcie_aspm=off"
  ];

  # Notes / workflow (kept here since it's directly related to this host module):
  #
  # Fresh install Lanzaboote workflow:
  # 1. BIOS -> Security -> Secure Boot -> "Clear Secure Boot Keys" (Setup Mode).
  # 2. Boot into NixOS (Secure Boot will be Off but in Setup Mode).
  # 3. Enter a temporary shell with sbctl:
  #      nix shell nixpkgs#sbctl
  # 4. Create keys:
  #      sudo sbctl create-keys --database-path /etc/secureboot
  # 5. Enroll keys (include Microsoft):
  #      sudo sbctl enroll-keys --microsoft --database-path /etc/secureboot
  # 6. Rebuild:
  #      sudo nixos-rebuild switch --flake .
  # 7. Reboot -> BIOS -> Turn Secure Boot ON.
}
