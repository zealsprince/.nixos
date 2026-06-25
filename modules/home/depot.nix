{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.home.depot;

  # The upload script is kept as a standalone file so it stays readable (and
  # testable) outside Nix. No runtimeInputs needed on macOS: it calls system
  # tools (curl, screencapture, pbcopy, osascript) by absolute path.
  depotUpload = pkgs.writeShellScriptBin "depot-upload" (
    builtins.readFile ./scripts/depot-upload.sh
  );
  exe = "${depotUpload}/bin/depot-upload";

  keyPath = config.age.secrets."depot-api-key".path;
in
{
  options.my.home.depot = {
    enable = lib.mkEnableOption "Hivecom depot upload script";

    url = lib.mkOption {
      type = lib.types.str;
      default = "https://depot.hivecom.net";
      description = "Depot gateway base URL.";
    };

    secretFile = lib.mkOption {
      type = lib.types.path;
      default = ../../secrets/depot-api-key.age;
      description = "agenix-encrypted file holding the depot API key (depot_...).";
    };

    keybinds = {
      enable = lib.mkEnableOption "skhd keybinds for depot upload (macOS only)";

      modifiers = lib.mkOption {
        type = lib.types.str;
        default = "cmd + alt + shift";
        description = "skhd modifier chord prefixed onto the depot keybinds.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets."depot-api-key".file = cfg.secretFile;

    home.packages = [ depotUpload ];

    # macOS hotkeys via skhd (a launchd user agent). The Linux WM binds
    # (Plasma/Hyprland) are handled separately, so this stays darwin-only.
    #
    # Key codes used instead of digits so the Shift modifier doesn't turn
    # "3" into "#" and break the match: 0x14=3, 0x15=4, 0x16=6 (0x17=5, video, later).
    services.skhd = lib.mkIf (cfg.keybinds.enable && pkgs.stdenv.isDarwin) {
      enable = true;
      config = ''
        # Hivecom depot upload (resulting URL lands on the clipboard)
        ${cfg.keybinds.modifiers} - 0x14 : DEPOT_URL=${cfg.url} DEPOT_KEY_FILE=${keyPath} ${exe} shot-full
        ${cfg.keybinds.modifiers} - 0x15 : DEPOT_URL=${cfg.url} DEPOT_KEY_FILE=${keyPath} ${exe} shot-region
        ${cfg.keybinds.modifiers} - 0x16 : DEPOT_URL=${cfg.url} DEPOT_KEY_FILE=${keyPath} ${exe} clipboard
      '';
    };
  };
}
