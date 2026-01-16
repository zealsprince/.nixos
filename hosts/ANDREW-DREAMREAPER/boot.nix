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
  boot.kernelPackages = pkgs.linuxPackages_latest;

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
