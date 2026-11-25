# Insecure packages we knowingly allow. Read by the NixOS hosts through
# modules/nixos/common.nix and by the standalone Home Manager package set in
# flake.nix, so both evaluate the same list.
[
  # nixpkgs flags Rider for CVE-2026-111497 in the .NET runtime JetBrains
  # bundles. The package swaps that runtime for nixpkgs' own, which carries the
  # patched Brotli, so the flag doesn't describe what gets installed. The fixed
  # 2026.3 can't be packaged yet. NixOS/nixpkgs#590447.
  "rider-2026.2.4"
]
