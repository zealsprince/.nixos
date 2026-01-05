{ pkgs, lib ? pkgs.lib, ... }:

/*
  Host-only custom packages module (niche tooling)

  Intent:
  - Keep "rare/specialized" apps out of shared package sets like `packages/desktop.nix`.
  - Import this module only from the specific host(s) that need the tooling, e.g.
      `./hosts/<HOST>/default.nix` -> `imports = [ ... ../../modules/nixos/packages/custom.nix ];`

  Notes:
  - Repo-local packages live under `.nixos/pkgs/*`.
  - This file is located at `.nixos/modules/nixos/packages/custom.nix`, so the path
    to `.nixos/pkgs/...` is `../../../pkgs/...`.
*/

let
  flex-designer = pkgs.callPackage ../../../pkgs/flex-designer { };
in
{
  environment.systemPackages = [
    flex-designer

    # FlexDesigner runtime deps (per upstream "apt-get install ..."):
    # - python3-pyaudio -> Python + PyAudio
    # - xdotool        -> X11 automation tool
    # - libvips        -> image processing library
    pkgs.python3
    pkgs.python3Packages.pyaudio
    pkgs.xdotool
    pkgs.vips
  ];
}
