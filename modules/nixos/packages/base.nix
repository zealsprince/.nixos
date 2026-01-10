{ pkgs, lib ? pkgs.lib, ... }:

{
  /*
    Base system packages (terminal-friendly)

    Intent:
    - Keep this module safe for terminal-only or server-ish systems.
    - Avoid GUI/desktop apps here (terminals, Steam, editors with GUI, etc.).
    - Prefer keeping “workflow/UI” packages in a desktop-specific module.

    Note:
    - Host-specific tooling should live under `hosts/<host>/...` or a dedicated profile module.
  */

  environment.systemPackages = with pkgs; [
    # Core tooling
    git
    gnupg
    vim-full
    wget
    tmux
    curl
    ripgrep
    fd
    jq
    unzip
    zip
    tree
    file
    rsync
    openssh
    bash
    coreutils
    gawk
    gnused
    ed
    rsync
    fzf
    zoxide
  ];
}
