{
  description = "zealsprince's NixOS + Home Manager flake";

  inputs = {
    # NixOS official package source, using the 25.11 branch
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

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

    # Real dotfiles (Zsh/Vim/Tmux/scripts). Kept separate from Nix config.
    # Use the remote GitHub repo so it works on any machine and is pinned via flake.lock.
    dotfiles = {
      url = "github:zealsprince/.dotfiles";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, lanzaboote, home-manager, ... }@inputs:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; config.allowUnfree = true; };
      system = pkgs.stdenv.hostPlatform.system;
    in
    {
      # -----------------------------------------------------------------------
      # NixOS configurations (host modules)
      # -----------------------------------------------------------------------
      nixosConfigurations = {
        ANDREW-DREAMREAPER = nixpkgs.lib.nixosSystem {
          inherit system;

          # Pass inputs to modules so modules can reference flake inputs when needed
          specialArgs = { inherit inputs; };

          modules = [
            # Host entrypoint (imports hardware + host boot + reusable modules)
            ./hosts/ANDREW-DREAMREAPER/default.nix

            # Home Manager as a NixOS module (host selects which HM "profile" to use)
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;

              # Pass inputs to home-manager modules as well (optional)
              home-manager.extraSpecialArgs = { inherit inputs; };

              home-manager.backupFileExtension = "backup";

              # Desktop host uses the desktop HM profile.
              # (The desktop profile should import ./home.nix as a base)
              home-manager.users.zealsprince = {
                imports = [ ./home.desktop.nix ];

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

          extraSpecialArgs = { inherit inputs; };

          modules = [
            ./home.nix
          ];
        };

        # Desktop Home Manager profile (GUI + WM + desktop package sets).
        zealsprince-desktop = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          extraSpecialArgs = { inherit inputs; };

          modules = [
            ./home.desktop.nix
          ];
        };
      };
    };
}
