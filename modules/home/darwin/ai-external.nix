{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.home.aiExternal;
in
{
  # ---------------------------------------------------------------------------
  # Local model servers on the Macs, with their weights on an external disk
  #
  # macOS only, and wired in as such: the flake hands this to the darwin home
  # configurations rather than ./home.nix, so no Linux host evaluates it. The
  # Linux side runs Ollama as a system service instead (my.services.ollama).
  #
  # Two parts, and the first one does most of the work:
  #
  # 1. Environment. Ollama, Draw Things and ComfyUI each want tens of gigabytes
  #    of models and each has its own idea of where those live. Pointing them at
  #    one root is just OLLAMA_MODELS and DRAWTHINGS_MODELS_DIR, after which the
  #    normal commands are the interface: `ollama pull`, `draw-things-cli`, the
  #    ComfyUI venv. Nothing wraps them.
  #
  # 2. serve-ai-external. The one thing with no native equivalent: bringing the
  #    three up headless with the right arguments, and saying whether they're
  #    up. gRPCServerCLI has no config file, so its models directory, port,
  #    weight cache and TLS have to live somewhere, and that somewhere is the
  #    options below.
  #
  # Layout under the root:
  #   ollama/models      OLLAMA_MODELS
  #   drawthings/models  gRPCServerCLI's argument, DRAWTHINGS_MODELS_DIR
  #   comfyui            the checkout, its .venv and its models/
  #   logs, run          one log and one pidfile per service
  #
  # The servers themselves aren't packaged here. Ollama, gRPCServerCLI-macOS and
  # the ComfyUI checkout are installed outside Nix, and the script names them
  # when it can't find one.
  # ---------------------------------------------------------------------------
  options.my.home.aiExternal = {
    # On by default, since the flake only hands this module to the Macs.
    enable = lib.mkEnableOption "local model servers with their weights on an external disk" // {
      default = true;
    };

    root = lib.mkOption {
      type = lib.types.str;
      default = "/Volumes/SSD/ai";
      description = "Directory holding every model store, log and pidfile. Overridable at runtime with EXTERNAL_AI_ROOT.";
    };

    ollama.host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:11434";
      description = "Address ollama serve binds, and the one status checks.";
    };

    drawThings.port = lib.mkOption {
      type = lib.types.port;
      default = 7859;
      description = "Port for gRPCServerCLI.";
    };

    drawThings.tls = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether the Draw Things server runs with TLS. Off suits a local server,
        and a client's own TLS setting has to match whatever this is.
      '';
    };

    drawThings.weightsCacheGiB = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = ''
        Weights held in memory between generations (the server's -w). It
        defaults to 0 upstream, which reloads the checkpoint every time.
      '';
    };

    comfyui.port = lib.mkOption {
      type = lib.types.port;
      default = 8188;
      description = "Port for the ComfyUI server.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      (pkgs.writeShellScriptBin "serve-ai-external" (
        # Defaults from the options, prepended so the script itself stays plain
        # shell: no Nix interpolation inside it, and it can be run or linted
        # standalone. EXTERNAL_AI_ROOT still overrides the root per invocation.
        ''
          AI_ROOT_DEFAULT=${lib.escapeShellArg cfg.root}
          OLLAMA_HOST_DEFAULT=${lib.escapeShellArg cfg.ollama.host}
          DRAWTHINGS_PORT_DEFAULT=${toString cfg.drawThings.port}
          DRAWTHINGS_TLS_DEFAULT=${if cfg.drawThings.tls then "1" else "0"}
          DRAWTHINGS_CACHE_DEFAULT=${toString cfg.drawThings.weightsCacheGiB}
          COMFYUI_PORT_DEFAULT=${toString cfg.comfyui.port}
        ''
        + builtins.readFile ./scripts/serve-ai-external.sh
      ))
    ];

    # The isolation layer. With these set, the tools' own commands already read
    # and write the external disk, which is why there's nothing wrapping them.
    home.sessionVariables = {
      EXTERNAL_AI_ROOT = cfg.root;
      OLLAMA_MODELS = "${cfg.root}/ollama/models";
      DRAWTHINGS_MODELS_DIR = "${cfg.root}/drawthings/models";
    };
  };
}
