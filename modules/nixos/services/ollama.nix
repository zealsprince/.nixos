{ config, lib, pkgs, ... }:

let
  cfg = config.my.services.ollama;

  # Prefer upstream NixOS module if present (services.ollama.*), but keep this
  # module self-contained by owning the unit when needed.
  #
  # NOTE: We avoid mkForce on services.ollama.enable unless the user opts into it,
  # so this can coexist with future upstream changes.
  resolvedPackage = cfg.package;

  hostStr =
    if cfg.listenAddress != null then cfg.listenAddress
    else if cfg.host != null then cfg.host
    else null;

  envHost =
    if hostStr == null then null
    else if lib.hasPrefix "http://" hostStr || lib.hasPrefix "https://" hostStr then hostStr
    else "http://${hostStr}";

  envAttrs =
    (lib.optionalAttrs (envHost != null) { OLLAMA_HOST = envHost; })
    // (lib.optionalAttrs (cfg.modelsPath != null) { OLLAMA_MODELS = cfg.modelsPath; })
    // cfg.extraEnvironment;

  accelEnv =
    if cfg.acceleration == "none" then { }
    else if cfg.acceleration == "cuda" then {
      # Common knobs used by Ollama / llama.cpp stacks.
      CUDA_VISIBLE_DEVICES = lib.mkDefault "0";
    }
    else if cfg.acceleration == "rocm" then {
      # ROCm often needs gfx override on some GPUs.
      # Do NOT use mkDefault here: systemd Environment entries must be plain strings,
      # and mkDefault produces an override set that can't be coerced to string.
      #
      # If you need this, set it via `my.services.ollama.extraEnvironment`.
      HSA_OVERRIDE_GFX_VERSION = "";
    }
    else { };

  mergedEnv = envAttrs // accelEnv;

  # Basic wrapper to turn attrs into systemd Environment= lines.
  envList =
    lib.mapAttrsToList (k: v: "${k}=${toString v}") mergedEnv;

in
{
  options.my.services.ollama = {
    enable = lib.mkEnableOption "Ollama model serving daemon (ollama serve)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.ollama;
      description = "Which Ollama package to install/provide (must include the `ollama` binary).";
    };

    startAtBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to start Ollama automatically at boot (multi-user target).";
    };

    # Prefer one canonical option, but keep compatibility with a `host` name the
    # user might expect.
    #
    # Examples:
    # - \"127.0.0.1:11434\"
    # - \"0.0.0.0:11434\"
    # - \"http://127.0.0.1:11434\"
    listenAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Address (and optionally scheme) for OLLAMA_HOST. If no scheme is provided, http:// is assumed.";
      example = "127.0.0.1:11434";
    };

    # Back-compat / convenience alias.
    host = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Alias for `listenAddress` (used to build OLLAMA_HOST).";
      example = "0.0.0.0:11434";
    };

    modelsPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional path for OLLAMA_MODELS (model storage directory).";
      example = "/var/lib/ollama/models";
    };

    acceleration = lib.mkOption {
      type = lib.types.enum [ "none" "cuda" "rocm" ];
      default = "none";
      description = "Hardware acceleration preference. This primarily adjusts environment and dependency hints; ensure the right drivers/toolkit are installed.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open TCP port 11434 in the firewall (only relevant when binding to non-localhost).";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "ollama";
      description = "System user to run the service as.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "ollama";
      description = "System group to run the service as.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/ollama";
      description = "Persistent state directory for Ollama (service working directory).";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra CLI arguments appended to `ollama serve`.";
      example = [ "--verbose" ];
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables for the service (merged with OLLAMA_HOST/OLLAMA_MODELS).";
      example = { OLLAMA_DEBUG = "1"; };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ resolvedPackage ];

    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.stateDir;
      createHome = true;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 ${cfg.user} ${cfg.group} -"
    ];

    # If you bind broadly, you probably want the firewall open.
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ 11434 ];

    systemd.services.ollama = {
      description = "Ollama model serving daemon";
      documentation = [
        "https://ollama.com"
        "https://github.com/ollama/ollama"
      ];

      wantedBy = lib.mkIf cfg.startAtBoot [ "multi-user.target" ];

      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;

        WorkingDirectory = cfg.stateDir;

        # Use upstream binary directly.
        ExecStart = lib.concatStringsSep " " ([
          "${resolvedPackage}/bin/ollama"
          "serve"
        ] ++ cfg.extraArgs);

        Environment = envList;

        Restart = "always";
        RestartSec = "2s";

        # Security hardening (reasonable defaults for a daemon with network access).
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = false;

        # Allow writing state/models under stateDir.
        ReadWritePaths = [ cfg.stateDir ];
      };
    };
  };
}
