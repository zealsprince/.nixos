{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.openrgb;
in
{
  options.hardware.openrgb = {
    motherboard = lib.mkOption {
      type = lib.types.enum [
        "amd"
        "intel"
        "none"
      ];
      default = "none";
      description = "Motherboard chipset type for SMBus driver loading (amd=i2c-piix4, intel=i2c-i801).";
    };
  };

  config = {
    # Load necessary kernel modules for SMBus/I2C access
    boot.kernelModules = [
      "i2c-dev"
    ]
    ++ lib.optional (cfg.motherboard == "amd") "i2c-piix4"
    ++ lib.optional (cfg.motherboard == "intel") "i2c-i801";

    # Provide the specific/latest udev rules downloaded manually.
    # This ensures support for newer devices that might not be in the stable package yet.
    services.udev.extraRules =
      builtins.replaceStrings [ "/bin/chmod" ] [ "${pkgs.coreutils}/bin/chmod" ]
        (builtins.readFile ./60-openrgb.rules);
  };
}
