{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    mkMerge
    types
    escapeSystemdPath;

  cfg = config.my.storage.ntfsMounts;

  # Build systemd mount option strings for a given mount point.
  # We use systemd.automount so the drives don't block boot and will mount on first access.
  mkSystemdUnitOptions = mountPoint: [
    "x-systemd.automount"
    "x-systemd.idle-timeout=${toString cfg.idleTimeoutSec}s"
    "x-systemd.device-timeout=${toString cfg.deviceTimeoutSec}s"
    "x-systemd.mount-timeout=${toString cfg.mountTimeoutSec}s"
    "x-systemd.after=local-fs-pre.target"
    "x-systemd.wanted-by=multi-user.target"
    "x-systemd.requires=local-fs-pre.target"
    "nofail"
  ] ++ lib.optionals cfg.allowUserMount [
    "user"
  ];

  mkNtfsFileSystem = name: m:
    let
      mountPoint = m.mountPoint;
      # In NixOS, "ntfs3" uses the in-kernel driver, while "ntfs" commonly maps to ntfs-3g.
      # We default to "ntfs3" for performance/features on modern kernels, but allow override.
      fsType =
        if m.driver == "ntfs3" then "ntfs3" else "ntfs";

      # Recommended baseline options for "data" drives:
      # - uid/gid: make the files owned by a user/group on Linux side
      # - umask: permissions mask for files/dirs on NTFS
      # - windows_names: disallow characters illegal on Windows
      # - big_writes: useful for ntfs-3g; ignored by ntfs3
      #
      # Note: NTFS doesn't support Unix permissions. Ownership/perm mapping is via mount options.
      baseOptions =
        [
          "uid=${toString cfg.ownerUid}"
          "gid=${toString cfg.ownerGid}"
          "umask=${cfg.umask}"
          "windows_names"
        ]
        ++ lib.optionals (m.driver == "ntfs-3g") [ "big_writes" ]
        ++ lib.optionals (m.readOnly) [ "ro" ]
        ++ mkSystemdUnitOptions mountPoint
        ++ m.extraOptions;
    in
    {
      ${mountPoint} = {
        device = m.device;
        inherit fsType;
        options = baseOptions;

        # Make the mount available during normal boot ordering.
        neededForBoot = false;
      };
    };

  # Ensure we have the right userspace helper available if the user selects ntfs-3g.
  # (The kernel ntfs3 driver doesn't need userspace helpers.)
  needsNtfs3g = lib.any (m: m.driver == "ntfs-3g") (lib.attrValues cfg.mounts);

in
{
  options.my.storage.ntfsMounts = {
    enable = mkEnableOption "reusable, host-defined NTFS auto-mounts (systemd automount)";

    mounts = mkOption {
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          # Prefer stable device paths like /dev/disk/by-uuid/XXXX or /dev/disk/by-label/LABEL
          device = mkOption {
            type = types.str;
            example = "/dev/disk/by-uuid/1234-ABCD";
            description = "Block device path for the NTFS filesystem.";
          };

          mountPoint = mkOption {
            type = types.str;
            example = "/mnt/Storage";
            description = "Where to mount the filesystem.";
          };

          driver = mkOption {
            type = types.enum [ "ntfs3" "ntfs-3g" ];
            default = "ntfs3";
            description = ''
              Which driver to use:
              - "ntfs3": in-kernel NTFS driver (recommended on modern kernels)
              - "ntfs-3g": FUSE driver (requires pkgs.ntfs3g)
            '';
          };

          readOnly = mkOption {
            type = types.bool;
            default = false;
            description = "Mount filesystem read-only.";
          };

          extraOptions = mkOption {
            type = types.listOf types.str;
            default = [ ];
            example = [ "nofail" "uid=1000" "gid=100" "umask=0022" ];
            description = "Additional mount options appended after module defaults.";
          };
        };
      }));

      default = { };
      example = {
        Storage = {
          device = "/dev/disk/by-uuid/DEADBEEF-0000-1111-2222-CAFEBABE0000";
          mountPoint = "/mnt/Storage";
          driver = "ntfs3";
        };
      };

      description = ''
        Host-defined NTFS mounts.

        Define each mount as an attribute; the key is only used for readability.
        Use stable device identifiers (e.g. /dev/disk/by-uuid/*) rather than /dev/sdX.
      '';
    };

    # Ownership and permission mapping defaults for NTFS.
    # These should generally match your primary user and group.
    ownerUid = mkOption {
      type = types.int;
      default = 1000;
      description = "Default uid used for NTFS ownership mapping (uid=...).";
    };

    ownerGid = mkOption {
      type = types.int;
      default = 100;
      description = "Default gid used for NTFS ownership mapping (gid=...).";
    };

    umask = mkOption {
      type = types.str;
      default = "0002";
      description = "Default umask for NTFS mounts (umask=...).";
    };

    allowUserMount = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to include the 'user' mount option.";
    };

    # Systemd automount tuning.
    idleTimeoutSec = mkOption {
      type = types.int;
      default = 300;
      description = "Seconds of inactivity before systemd auto-unmounts the filesystem.";
    };

    deviceTimeoutSec = mkOption {
      type = types.int;
      default = 10;
      description = "Seconds to wait for the block device to appear before giving up (systemd).";
    };

    mountTimeoutSec = mkOption {
      type = types.int;
      default = 30;
      description = "Seconds systemd will wait for the mount operation to complete.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Ensure mount points exist.
    {
      systemd.tmpfiles.rules =
        map (m: "d ${m.mountPoint} 0755 ${toString cfg.ownerUid} ${toString cfg.ownerGid} - -")
          (lib.attrValues cfg.mounts);
    }

    # Add the fileSystems entries.
    {
      fileSystems = mkMerge (lib.mapAttrsToList mkNtfsFileSystem cfg.mounts);
    }

    # If explicitly using ntfs-3g, ensure the helper is present.
    (mkIf needsNtfs3g {
      environment.systemPackages = [ pkgs.ntfs3g ];
    })
  ]);
}
