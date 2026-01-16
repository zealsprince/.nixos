# Legacy `configuration.nix` kept for convenience.
#
# The flake uses `./hosts/<hostname>/default.nix` as the primary entrypoint.
# This file delegates to a host module so:
# - `nixos-rebuild switch -I nixos-config=...` workflows still work, and
# - the repository remains approachable to readers expecting a `configuration.nix`.
#
# NOTE:
# - This file cannot reliably infer the host module from `config.networking.hostName`
#   because `imports` are evaluated before `config` is fully built.
# - A concrete host module is selected below; adjust as needed per machine.

{ ... }:

{
  imports = [
    ./hosts/ANDREW-DREAMREAPER/default.nix
  ];

  # Keep this file minimal on purpose.
  #
  # If changes must be added here, prefer putting them under:
  # - `./modules/nixos/*` for reusable NixOS settings, or
  # - `./hosts/<hostname>/*` for machine-specific settings.
}
