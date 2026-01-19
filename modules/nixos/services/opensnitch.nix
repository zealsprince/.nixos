{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.services.opensnitch;

  # Use the packaged defaults as a base, but force the process monitor method to
  # the one selected via NixOS (e.g. "proc" to avoid kernel/ebpf incompat).
  packagedDefaultConfigPath = "${cfg.package}/etc/opensnitchd/default-config.json";
  packagedSystemFwPath = "${cfg.package}/etc/opensnitchd/system-fw.json";

  packagedDefaultConfig = builtins.fromJSON (builtins.readFile packagedDefaultConfigPath);

  generatedDefaultConfig = packagedDefaultConfig // {
    ProcMonitorMethod = cfg.monitorMethod;
  };

  generatedDefaultConfigText = builtins.toJSON generatedDefaultConfig;
in
{
  options.my.services.opensnitch = {
    enable = lib.mkEnableOption "OpenSnitch firewall application daemon (opensnitchd)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.opensnitch;
      description = "Which OpenSnitch package to install/provide (must include opensnitchd).";
    };

    # Most people want OpenSnitch active at boot, but this keeps parity with your other service modules.
    startAtBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to start OpenSnitch daemon automatically at boot (multi-user target).";
    };

    # Persistent state (rules + optional runtime config we manage).
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/opensnitch";
      description = "Persistent state directory for OpenSnitch.";
    };

    rulesDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.stateDir}/rules";
      description = "Persistent directory for OpenSnitch rules.";
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/opensnitchd";
      description = "Persistent configuration directory for OpenSnitch daemon.";
    };

    configFile = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.configDir}/default-config.json";
      description = "Config file path passed to opensnitchd via --config-file.";
    };

    monitorMethod = lib.mkOption {
      type = lib.types.enum [
        "ebpf"
        "proc"
        "ftrace"
        "audit"
      ];
      default = "ebpf";
      description = "Method to monitor processes.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Ensure state directories exist and persist between rebuilds.
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 root root -"
      "d ${cfg.rulesDir} 0755 root root -"
    ];

    # Manage OpenSnitch config files via Nix so they always exist, regardless of
    # tmpfiles/service start ordering.
    #
    # Note: OpenSnitch expects these paths (and the GUI relies on them).
    environment.etc."opensnitchd/default-config.json".text = generatedDefaultConfigText;
    environment.etc."opensnitchd/system-fw.json".source = packagedSystemFwPath;

    # We fully own the unit to avoid fragment/drop-in composition issues and
    # ensure a single authoritative ExecStart (systemd refuses multiple ExecStart=
    # lines for Type=simple services).
    services.opensnitch.enable = lib.mkForce false;

    systemd.services.opensnitchd = {
      description = "Application firewall OpenSnitch";
      documentation = [ "https://github.com/evilsocket/opensnitch/wiki" ];

      wantedBy = lib.mkIf cfg.startAtBoot [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/opensnitchd --config-file ${cfg.configFile} -rules-path ${cfg.rulesDir} -process-monitor-method ${cfg.monitorMethod}";
        Restart = "always";
        RestartSec = "30";
        TimeoutStopSec = "10";

        # OpenSnitch needs privileges to interface with firewall/packet filtering.
        User = "root";
        Group = "root";
      };
    };
  };
}
