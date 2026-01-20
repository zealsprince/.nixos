{ ... }:

{
  # Service modules (delegator).
  #
  # Keep this file as a stable import target so hosts can simply import
  # `modules/nixos/services.nix` and pick up any service modules we add under
  # `modules/nixos/services/`.
  #
  # Individual service modules should define options under your namespace
  # (e.g. `my.services.<name>.enable`) and map them to upstream NixOS options.

  imports = [
    ./services/ckb-next.nix
    ./services/openlinkhub.nix
    ./services/opensnitch.nix
    ./services/mullvad.nix
    ./services/ollama.nix
    ./services/virtuoso-sidetone.nix
    ./services/samba.nix
  ];
}
