{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.0.20260714.251828";
in
stdenvNoCC.mkDerivation {
  pname = "steam-runtime-scout-sdk";
  inherit version;

  # Pinned snapshot instead of latest-steam-client-general-availability, which
  # moves. Hashes for each snapshot are in its SHA256SUMS.
  src = fetchurl {
    url = "https://repo.steampowered.com/steamrt-images-scout/snapshots/${version}/com.valvesoftware.SteamRuntime.Sdk-amd64,i386-scout-sysroot.tar.gz";
    sha256 = "f54decb12adcb762e83efe7d8900361f6de5b4e462ad141625a20ed694f7c9cf";
  };

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out
    tar -xzf $src -C $out --no-same-owner --no-same-permissions
  '';

  # This is a foreign root that gets chrooted into. Patching shebangs or ELF
  # interpreters to /nix/store paths would break it from the inside.
  dontFixup = true;

  meta = {
    description = "Steam Runtime 1 'scout' SDK sysroot";
    homepage = "https://gitlab.steamos.cloud/steamrt/scout/sdk";
    license = lib.licenses.unfreeRedistributable;
    platforms = [ "x86_64-linux" ];
  };
}
