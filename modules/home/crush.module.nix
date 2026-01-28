{
  config,
  lib,
  pkgs,
  ...
}:
# TODO: Delete this module once Crush is fixed upstream to work with Home Manager directly.
let
  cfg = config.programs.crush;
  # Use the package from NUR via the inputs passed in specialArgs
  # We use pkgs.nur (configured via overlay in host config) to ensure system config (allowUnfree) is respected.
  defaultPackage = pkgs.nur.repos.charmbracelet.crush;
  jsonFormat = pkgs.formats.json { };
in
{
  options.programs.crush = {
    enable = lib.mkEnableOption "Crush AI coding agent";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = "The Crush package to install.";
    };

    settings = lib.mkOption {
      type = jsonFormat.type;
      default = { };
      description = ''
        Configuration written to ~/.config/crush/crush.json.
        See https://github.com/charmbracelet/crush for available options.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    home.file.".config/crush/crush.json" = lib.mkIf (cfg.settings != { }) {
      source = jsonFormat.generate "crush.json" cfg.settings;
    };
  };
}
