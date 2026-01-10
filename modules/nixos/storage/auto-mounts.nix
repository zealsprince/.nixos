{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    mkMerge
    types;

  cfg = config.my.storage.autoMounts;

  # Build systemd mount option strings for a given mount point.
  # We use systemd.automount so the drives don't block boot and will mount on first access.
  mkSystemdUnitOptions = mountPoint: [
    "x-systemd.automount"
    "x-systemd.idle-timeout=${toString cfg.idleTimeoutSec}s"
    "x-systemd.device-timeout=${toString cfg.deviceTimeoutSec}s"
    "x-systemd.mount-timeout=${toString cfg.mountTimeoutSec}s"
    "x-systemd.wanted-by=multi-user.target"
    "nofail"
  ] ++ lib.optionals cfg.allowUserMount [
    "user"
  ];

  mkAutoFileSystem = name: m:
    let
      mountPoint = m.mountPoint;
      fsType = m.fsType;

      # Identify if filesystem is non-POSIX (FAT/NTFS/exFAT) and needs permission mapping.
      isNonPosix = builtins.elem fsType [ "vfat" "exfat" "ntfs" "ntfs3" ];

      # Recommended baseline options for typical "data" drives.
      #
      # Notes:
      # - Most non-POSIX filesystems (NTFS, exFAT, FAT) don't support Unix permissions;
      #   ownership/permissions are mapped via mount options.
      # - "windows_names" is only meaningful for NTFS.
      baseOptions =
        lib.optionals isNonPosix [
          "uid=${toString cfg.ownerUid}"
          "gid=${toString cfg.ownerGid}"
          "umask=${cfg.umask}"
        ]
        ++ lib.optionals (fsType == "ntfs3" || fsType == "ntfs") [ "windows_names" ]
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
        noCheck = true;
      };
    };

  # Userspace helpers (only needed for some fsTypes).
  needsNtfs3g = lib.any (m: m.fsType == "ntfs") (lib.attrValues cfg.mounts);
  needsExfatProgs = lib.any (m: m.fsType == "exfat") (lib.attrValues cfg.mounts);

in
{
  options.my.storage.autoMounts = {
    enable = mkEnableOption "reusable, host-defined auto-mounts (systemd automount)";

    mounts = mkOption {
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          # Prefer stable device paths like /dev/disk/by-uuid/XXXX or /dev/disk/by-label/LABEL
          device = mkOption {
            type = types.str;
            example = "/dev/disk/by-uuid/1234-ABCD";
            description = "Block device path for the filesystem.";
          };

          mountPoint = mkOption {
            type = types.str;
            example = "/mnt/Storage";
            description = "Where to mount the filesystem.";
          };

          fsType = mkOption {
            type = types.str;
            default = "ntfs3";
            example = "exfat";
            description = ''
              Filesystem type for this mount (maps to `fileSystems.<mountPoint>.fsType`).

              Common values:
              - "ntfs3": in-kernel NTFS driver (recommended on modern kernels)
              - "ntfs": ntfs-3g userspace driver (requires pkgs.ntfs3g)
              - "exfat": exFAT (requires pkgs.exfatprogs)
              - "ext4", "xfs", "btrfs": Linux-native filesystems (usually no extra packages needed)
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
          fsType = "ntfs3";
        };
      };

      description = ''
        Host-defined auto-mounts.

        Define each mount as an attribute; the key is only used for readability.
        Use stable device identifiers (e.g. /dev/disk/by-uuid/*) rather than /dev/sdX.
      '';
    };

    # Ownership and permission mapping defaults for non-POSIX filesystems.
    # These should generally match your primary user and group.
    ownerUid = mkOption {
      type = types.int;
      default = 1000;
      description = "Default uid used for ownership mapping (uid=...).";
    };

    ownerGid = mkOption {
      type = types.int;
      default = 100;
      description = "Default gid used for ownership mapping (gid=...).";
    };

    umask = mkOption {
      type = types.str;
      default = "0002";
      description = "Default umask for mounts (umask=...).";
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
      fileSystems = mkMerge (lib.mapAttrsToList mkAutoFileSystem cfg.mounts);
    }

    # Ensure kernel support and userspace tools are available.
    (mkIf needsNtfs3g {
      boot.supportedFilesystems = [ "ntfs" ];
      environment.systemPackages = [ pkgs.ntfs3g ];
    })

    (mkIf needsExfatProgs {
      boot.supportedFilesystems = [ "exfat" ];
      environment.systemPackages = [ pkgs.exfatprogs ];
    })
  ]);
}
