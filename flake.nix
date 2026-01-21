{
  description = "zealsprince's NixOS + Home Manager flake";

  inputs = {
    # NixOS official package source, using the 25.11 branch
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    # Unstable for bleeding-edge packages (e.g. newer Ollama)
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    _1password-shell-plugins.url = "github:1Password/shell-plugins";

    # Home Manager, following the same release version
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
    };

    nixpkgs-howdy.url = "github:fufexan/nixpkgs/howdy";

    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    kwin-effects-forceblur = {
      url = "github:taj-ny/kwin-effects-forceblur";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    affinity-nix = {
      url = "github:mrshmllow/affinity-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # mio-19 NUR (contains pkgs/plezy)
    mio19-nurpkgs = {
      url = "github:mio-19/nurpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Real dotfiles (Zsh/Vim/Tmux/scripts). Kept separate from Nix config.
    # Use the remote GitHub repo so it works on any machine and is pinned via flake.lock.
    dotfiles = {
      url = "github:zealsprince/.dotfiles";
      flake = false;
    };

    neko-zed-dark = {
      url = "github:zealsprince/neko-zed-dark";
      flake = false;
    };

    # -------------------------------------------------------------------------
    # THEME INPUTS (placeholders you can swap out later)
    #
    # Goal:
    # - `hyprlands`: your Hyprland themes repo (pinned via flake.lock)
    #
    # Live iteration:
    # - keep a local checkout on disk (not a flake input)
    # - point your Home Manager module at that local path when you want fast edits
    #   (e.g. `~/Projects/hypr-themes/themes/<name>`)
    # -------------------------------------------------------------------------

    # Hyprland themes repo (raw files, not a flake)
    hyprlands = {
      url = "github:zealsprince/hyprlands";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      lanzaboote,
      home-manager,
      ...
    }@inputs:
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };
      pkgs-unstable = import nixpkgs-unstable {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };
    in
    {
      # -----------------------------------------------------------------------
      # NixOS configurations (host modules)
      # -----------------------------------------------------------------------
      nixosConfigurations = {
        ANDREW-DREAMREAPER = nixpkgs.lib.nixosSystem {
          # Pass inputs to modules so modules can reference flake inputs when needed
          specialArgs = {
            inherit inputs;
            inherit pkgs-unstable;
          };

          modules = [
            inputs.nur.modules.nixos.default
            inputs.nur.legacyPackages.x86_64-linux.repos.charmbracelet.modules.nixos.crush
            inputs.agenix.nixosModules.default

            # Host entrypoint (imports hardware + host boot + reusable modules)
            ./hosts/ANDREW-DREAMREAPER/default.nix

            # Home Manager as a NixOS module (host selects which HM "profile" to use)
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;

              # Pass inputs to home-manager modules as well (optional)
              home-manager.extraSpecialArgs = {
                inherit inputs;
                inherit pkgs-unstable;
              };

              home-manager.backupFileExtension = "backup";

              # Desktop host uses the desktop HM profile.
              # (The desktop profile should import ./home.nix as a base)
              home-manager.users.zealsprince = {
                imports = [
                  inputs.agenix.homeManagerModules.default
                  ./home.desktop.nix
                ];

                # AMD-specific desktop addons (ROCm, etc.)
                my.home.packages.desktop.amd.enable = true;
              };
            }

            # Lanzaboote module (host module enables/configures it)
            lanzaboote.nixosModules.lanzaboote

            # Shell plugins module (used by system config)
            inputs._1password-shell-plugins.nixosModules.default

            # Howdy module definition (service module comes from the input)
            "${inputs.nixpkgs-howdy}/nixos/modules/services/security/howdy"
          ];
        };
      };

      # -----------------------------------------------------------------------
      # Home Manager configurations (works on NixOS and non-NixOS "nix only")
      # -----------------------------------------------------------------------
      homeConfigurations = {
        # Base (CLI/headless-friendly) Home Manager profile.
        zealsprince = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          extraSpecialArgs = {
            inherit inputs;
            inherit pkgs-unstable;
          };

          modules = [
            inputs.agenix.homeManagerModules.default
            ./home.nix
          ];
        };

        # Desktop Home Manager profile (GUI + WM + desktop package sets).
        zealsprince-desktop = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          extraSpecialArgs = {
            inherit inputs;
            inherit pkgs-unstable;
          };

          modules = [
            inputs.agenix.homeManagerModules.default
            ./home.desktop.nix
          ];
        };
      };
    };
}
