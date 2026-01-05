{ pkgs, inputs, lib ? pkgs.lib, ... }:

{
  # System package sets.
  #
  # This module is kept as a delegator so callers can continue importing
  # `modules/nixos/packages.nix`.
  #
  # IMPORTANT:
  # We only import the "safe everywhere" base package set here.
  #
  # Desktop / GUI packages should be imported explicitly by the relevant host or
  # desktop profile modules (e.g. Plasma vs Hyprland) so we don't accidentally
  # pull KDE/Plasma apps into non-Plasma systems.
  imports = [
    ./packages/base.nix
  ];
}
