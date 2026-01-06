# .nixos

This repository is a **flake-based** Nix configuration designed for modularity and reusability. It supports:

- **NixOS** system configuration (per-host)
- **Home Manager** user configuration (generic + portable)
- A clean separation between:
  - **Host-specific** hardware/boot settings (e.g., Secure Boot, disk layout)
  - **Reusable** modules (desktop environments, programs, defaults)
  - **WM-specific** Home Manager configuration

## Philosophy

The goal of this structure is to keep the "OS" configuration cleanly separated from "User" configuration, while allowing code reuse across multiple machines.

1.  **Host-specific things live under `hosts/<hostname>/`**:
    - Disk layout (`hardware-configuration.nix`)
    - Bootloader settings
    - Machine specific drivers/quirks
    
2.  **Reusable system modules live under `modules/nixos/`**:
    - Desktop environments (e.g., Plasma)
    - Program configurations (e.g., 1Password, Steam)
    - Security modules (e.g., Howdy)

3.  **Home Manager is split by workflow**:
    - Base config (`modules/home/base.nix`) works on any machine (NixOS or Linux/macOS with Nix).
    - Window Manager configs (`modules/home/wm/`) contain desktop-specific autostarts and shortcuts.

## Directory Layout

```text
.
├── flake.nix                  # Entrypoint: defines inputs and outputs
├── home.nix                   # Base Home Manager entrypoint
├── home.desktop.nix           # Extended Home Manager profile for GUI/Desktop usage
├── hosts/                     # Machine-specific configurations
│   └── YOUR_HOSTNAME/
│       ├── default.nix        # Host entrypoint (imports hardware + reusable modules)
│       ├── hardware-configuration.nix # Generated hardware config
│       └── boot.nix           # Bootloader / Secure Boot settings
└── modules/
    ├── nixos/                 # System-level modules
    └── home/                  # User-level modules
```

## Getting Started

### 1. External Dotfiles (Optional)

This configuration is designed to work alongside a separate "vanilla" dotfiles repository (referenced as `inputs.dotfiles` in `flake.nix`). This allows you to keep your shell scripts, Zsh, and Vim configs portable to non-Nix systems.

- **If you have your own dotfiles repo**: Update the `dotfiles` input url in `flake.nix`.
- **If you prefer Nix-native config**: Remove the `dotfiles` input and adjust `home.nix` to define files inline.

### 2. Customizing for Your User

1.  Open `flake.nix`.
2.  Locate `homeConfigurations`.
3.  Rename the user key (e.g., `zealsprince`) to your actual username.
4.  Update `modules/home/base.nix` with your username, home directory, and git details.

### 3. Adding a New NixOS Host

To add a new machine:

1.  Create a folder: `hosts/MY-MACHINE/`.
2.  Generate hardware config:
    ```bash
    nixos-generate-config --show-hardware-config > hosts/MY-MACHINE/hardware-configuration.nix
    ```
3.  Create `hosts/MY-MACHINE/default.nix`. Import your hardware config and any shared modules you want (see existing hosts for examples).
4.  Register the host in `flake.nix` under `nixosConfigurations`.

## Usage

### NixOS (System Update)
From the directory root:

```bash
sudo nixos-rebuild switch --flake .#YOUR_HOSTNAME
```

### Home Manager (User Update)
Can be run on NixOS or any system with Nix installed:

```bash
home-manager switch --flake .#YOUR_USERNAME
```

## Notes

- **`configuration.nix`**: Kept as a legacy delegator but not actively used. The real entry points are in `hosts/*/default.nix`.
- **Secure Boot**: This setup supports Lanzaboote. Ensure you generate keys and enroll them if you enable the secure boot module on a host.