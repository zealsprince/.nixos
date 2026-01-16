{ ... }:

{
  # Allow mounting/unlocking drives from KDE/Dolphin "Devices" without a password prompt,
  # but only for your user, only when you're physically present (local) and active.
  #
  # This affects udisks2-driven mounts/unlocks (the GUI sidebar devices), not the
  # systemd/fstab mounts under /mnt.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      // Filesystem mount actions
      var isMountAction =
        action.id == "org.freedesktop.udisks2.filesystem-mount" ||
        action.id == "org.freedesktop.udisks2.filesystem-mount-system";

      // LUKS unlock actions (harmless if you don't use them for these disks)
      var isUnlockAction =
        action.id == "org.freedesktop.udisks2.encrypted-unlock" ||
        action.id == "org.freedesktop.udisks2.encrypted-unlock-system";

      if (!(isMountAction || isUnlockAction)) {
        return;
      }

      // Only allow for your user, only when they're at the local session and active.
      // This prevents granting this permission over SSH/background sessions.
      if (subject.user == "zealsprince" && subject.local && subject.active) {
        return polkit.Result.YES;
      }
    });
  '';
}
