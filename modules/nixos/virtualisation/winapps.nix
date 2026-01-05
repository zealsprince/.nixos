{ config, lib, pkgs, ... }:

let
  cfg = config.my.virtualisation.winapps;

  # Basic hardening of user-provided strings that end up in shell scripts.
  # This is not meant to be perfect; it just prevents accidental unescaped whitespace.
  escape = lib.escapeShellArg;

  # Generate a desktop entry for each declared app.
  mkDesktopItem = name: app:
    let
      # Exec wrapper defined below (installed into /run/current-system/sw/bin).
      execBin = "winapp-${lib.toLower (lib.replaceStrings [ " " ] [ "-" ] name)}";
      desktopName = app.desktopName or name;
      comment = app.comment or "Windows app (via RDP to VM)";
      categories = app.categories or [ "Office" ];
      icon = app.icon or "windows";
    in
    pkgs.makeDesktopItem {
      inherit categories comment icon;
      name = execBin;
      desktopName = desktopName;
      exec = execBin;
      terminal = false;
      type = "Application";
    };

  mkExecWrapper = name: app:
    let
      execBin = "winapp-${lib.toLower (lib.replaceStrings [ " " ] [ "-" ] name)}";

      # If you're using RemoteApp, FreeRDP wants a "remote application program".
      # Many setups use aliases like "||program" on Windows, but plain exe names
      # (e.g. "notepad") are also common depending on the RDP host configuration.
      #
      # For Affinity (Photo/Designer/Publisher), you'll likely point to an explicit
      # EXE path on the Windows side.
      remoteProgram = app.remoteProgram;

      # Optional working directory hint (some apps behave better with it).
      remoteWorkingDir = app.remoteWorkingDir or null;

      # Resolution / windowing
      sizeArg =
        if app ? size && app.size != null then
          "/size:${app.size}"
        else if cfg.fullscreen then
          "/f"
        else
          "+dynamic-resolution";

      # Share a host folder into the RDP session. This is extremely handy to move
      # files between Linux and Windows.
      #
      # Note: how this mounts in Windows depends on RDP client behavior; in most
      # cases it appears as a drive under "This PC" or in the redirected devices.
      driveArgs = lib.concatStringsSep " " (lib.mapAttrsToList
        (driveName: hostPath: "/drive:${escape driveName},${escape hostPath}")
        cfg.drives);

      # Remote app args (optional).
      programArgs =
        if app ? remoteProgramArgs && app.remoteProgramArgs != null then
          # FreeRDP expects /app-cmd:<string>. Keep it as-is but shell-escaped.
          "/app-cmd:${escape app.remoteProgramArgs}"
        else
          "";

      workingDirArgs =
        if remoteWorkingDir != null then
          "/app-workdir:${escape remoteWorkingDir}"
        else
          "";

      # Credentials: prefer NLA. You can provide user/password, but password in the
      # Nix store is a footgun; use a runtime prompt by omitting it, or use a
      # secret manager wrapper yourself.
      #
      # FreeRDP prompts if /p is not provided (depending on build/options).
      credArgs =
        let
          userArg = if cfg.username != null then "/u:${escape cfg.username}" else "";
          passArg = if cfg.password != null then "/p:${escape cfg.password}" else "";
          domainArg = if cfg.domain != null then "/d:${escape cfg.domain}" else "";
        in
        lib.concatStringsSep " " (lib.filter (s: s != "") [ userArg passArg domainArg ]);

      # Security args
      secArgs = lib.concatStringsSep " " ([
        "/cert:${cfg.certPolicy}"
        "+clipboard"
        "+auto-reconnect"
        "+glyph-cache"
        "+fonts"
        "+aero"
      ] ++ (lib.optionals cfg.enableAudio [ "+audio" ]));
    in
    pkgs.writeShellScriptBin execBin ''
      set -euo pipefail

      if ! command -v xfreerdp >/dev/null 2>&1; then
        echo "xfreerdp not found. Ensure my.virtualisation.winapps.enable = true." >&2
        exit 1
      fi

      # RemoteApp mode: use /app:program (or /app:||program depending on Windows host config).
      #
      # NOTE: If RemoteApp is not configured on the Windows VM, you can disable
      # it per-app and fall back to a normal desktop session.
      if [ "${lib.boolToString (app.remoteApp or true)}" = "true" ]; then
        exec xfreerdp \
          /v:${escape cfg.host} \
          /port:${toString cfg.port} \
          ${credArgs} \
          ${secArgs} \
          ${sizeArg} \
          ${driveArgs} \
          /app:${escape remoteProgram} \
          ${workingDirArgs} \
          ${programArgs} \
          ${cfg.extraRdpArgs}
      else
        exec xfreerdp \
          /v:${escape cfg.host} \
          /port:${toString cfg.port} \
          ${credArgs} \
          ${secArgs} \
          ${sizeArg} \
          ${driveArgs} \
          ${cfg.extraRdpArgs}
      fi
    '';

in
{
  options.my.virtualisation.winapps = {
    enable = lib.mkEnableOption "WinApps-style Windows app launching via libvirt + RDP (NAT VM assumed)";

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        RDP endpoint for the Windows VM.

        For a NAT-only libvirt VM, this is typically:
        - a forwarded host port (recommended), e.g. 127.0.0.1:3389 -> VM:3389, or
        - the VM's NAT IP (less stable), e.g. 192.168.122.x

        This module does not create port forwards; it only provides the client
        side of the workflow.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3389;
      description = "RDP port to connect to.";
    };

    username = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Windows username for RDP. If null, FreeRDP may prompt or use other auth mechanisms.";
    };

    password = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Windows password for RDP.

        WARNING: putting a password in Nix configuration can leak into the Nix store.
        Prefer leaving this null and providing credentials interactively, or wrap the
        launcher to fetch secrets from a password manager at runtime.
      '';
    };

    domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional Windows domain/workgroup.";
    };

    certPolicy = lib.mkOption {
      type = lib.types.enum [ "ignore" "tofu" "ask" "deny" ];
      default = "tofu";
      description = "FreeRDP certificate handling policy.";
    };

    enableAudio = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable audio redirection.";
    };

    fullscreen = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Launch RDP sessions fullscreen by default (unless per-app size is specified).";
    };

    drives = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Host directories to expose to Windows via RDP drive redirection.

        Example:
          my.virtualisation.winapps.drives = {
            "Zeal" = "/mnt/Zeal";
            "Downloads" = "/home/zealsprince/Downloads";
          };
      '';
    };

    extraRdpArgs = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Extra arguments appended to every xfreerdp invocation.";
    };

    apps = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          desktopName = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Desktop entry display name. Defaults to the attribute name.";
          };

          comment = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Desktop entry comment/description.";
          };

          categories = lib.mkOption {
            type = lib.types.nullOr (lib.types.listOf lib.types.str);
            default = null;
            description = "Desktop entry categories.";
          };

          icon = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Desktop entry icon name (from your icon theme) or an absolute path.

              Tip: you can point to an extracted Windows icon file if you manage it yourself.
            '';
          };

          remoteApp = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to use RemoteApp mode. If false, launches a full desktop RDP session.";
          };

          remoteProgram = lib.mkOption {
            type = lib.types.str;
            description = ''
              RemoteApp program identifier.

              Examples:
              - "notepad"
              - "C:\\Program Files\\Affinity\\Photo 2\\Photo.exe"
              - "||notepad" (depends on Windows RemoteApp config)

              For Affinity, you'll typically want the full EXE path.
            '';
          };

          remoteProgramArgs = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Optional command-line arguments passed to the RemoteApp program.";
          };

          remoteWorkingDir = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Optional working directory for the RemoteApp program.";
          };

          size = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Optional FreeRDP size argument, e.g. "1920x1080".
              If set, overrides fullscreen/dynamic resolution defaults.
            '';
          };
        };
      }));
      default = { };
      description = "Windows apps to expose as Linux desktop launchers.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Host-side components
    virtualisation.libvirtd = {
      enable = true;

      qemu = {
        # OVMF is available by default on current NixOS; the old `ovmf` submodule
        # was removed, so don't configure it here.
        swtpm.enable = true;
      };
    };

    programs.virt-manager.enable = true;

    environment.systemPackages =
      [
        pkgs.freerdp
        pkgs.virt-viewer
      ]
      ++ (lib.mapAttrsToList mkDesktopItem cfg.apps)
      ++ (lib.mapAttrsToList mkExecWrapper cfg.apps);

    # NAT-only is the default libvirt networking mode; no bridging is configured here.
  };
}
