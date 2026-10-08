{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  dbus,
  libGL,
  libx11,
  libxcursor,
  libxi,
  libxcb,
  libxkbcommon,
  vulkan-loader,
  wayland,
  app,
}:

let
  # ArtCraft's Crafting Apps (https://getartcraft.com). Each is its own repo
  # under github.com/storytold with the same release layout. The hashes are
  # each release's SHA256SUMS.txt converted to SRI.
  apps = {
    cadcraft = {
      version = "0.3.0";
      description = "Computer-aided design";
      x86_64-linux = "sha256-QjmwVFwABsE/ZBn+m8IEYtcnCWkSzzyx6yUjk0ECvXg=";
      aarch64-linux = "sha256-7hTByZ4JK0b27+foCdSp6kGnekNtId3S81rj8VQpNWM=";
    };

    deckcraft = {
      version = "0.3.0";
      description = "Presentation editor";
      x86_64-linux = "sha256-F51s5HQBujfCM8P8ChgDQSau2BrDaknE327NrKm1q38=";
      aarch64-linux = "sha256-/h2TbH5nNxq6Lj7Yb/6bwgcgpuH/Wwo5DIIoO7lMJD8=";
    };

    designcraft = {
      version = "0.4.0";
      description = "Page layout";
      x86_64-linux = "sha256-TAtowNxiCB5FW/jWDdVPAi/xYkNZ1eENBsorGNc9S7M=";
      aarch64-linux = "sha256-G1uQVpWa2lKQqizarYUHSMn58JocO0E2kIurmWsrtFw=";
    };

    effectcraft = {
      version = "0.6.0";
      description = "Motion graphics editor";
      x86_64-linux = "sha256-cYEHGZAzeM2rMqH+Mo8jyHTTjNPYM6uxnGJj3SutIYw=";
      aarch64-linux = "sha256-d8xXa5sce2Q26ZfySoxQsFeD9svlc6rqoOx+EFh3RY4=";
    };

    filmcraft = {
      version = "0.4.0";
      description = "Video editor";
      x86_64-linux = "sha256-hBeQ/2ZJ8NSdqkqK3hyxjZSOXKQ9AHcQRmY+BsjYzoM=";
      aarch64-linux = "sha256-P7/JtJoCv6imumvX8YQXc7Ymoq3wkY9eYWQpnT8S8UQ=";
    };

    gridcraft = {
      version = "0.3.0";
      description = "Spreadsheet";
      x86_64-linux = "sha256-5RWuiK4kgKBKS10klUDugqxSHQvouGu8qPVlR7yBVP8=";
      aarch64-linux = "sha256-wgDPavK12pkjnxDoNqbnrZxNxMUMpEmDcA0dlgv1Dis=";
    };

    lightcraft = {
      version = "0.4.0";
      description = "Photo library and raw developer";
      x86_64-linux = "sha256-wsdXgLzwWKIcSjEc5X20flnwrC9t1wRYM3aa4QA7VyM=";
      aarch64-linux = "sha256-adhCWwswyXOizAcrJc+QMQgcFEvEPlK3zqci656KgQA=";
    };

    pdfcraft = {
      version = "0.4.0";
      description = "PDF editor";
      x86_64-linux = "sha256-SHmzzbTRJhlFrwOxxfAPPoaNBehOd5EZYMrFBaoWwds=";
      aarch64-linux = "sha256-CLL/bFOK2zzAioiBSjzObu4Jy5jJr5NMOTpRMaMVWQ4=";
    };

    photocraft = {
      version = "0.5.0";
      description = "Image editor";

      # Its startup check looks for the display libs through ldconfig and
      # /usr/lib, so it never sees RUNPATH and refuses to launch.
      env.PHOTOCRAFT_SKIP_LIB_CHECK = "1";

      x86_64-linux = "sha256-4EQQGy2lUiiW4dgza4EIfL7L9reLdoUxX1jdTz36TOA=";
      aarch64-linux = "sha256-OQT8nKtFsIPVhwqNT6uQs6lMO6VUemNrt79aOY2pxVI=";
    };

    soundcraft = {
      version = "0.3.0";
      description = "Digital audio workstation";
      x86_64-linux = "sha256-MdSj5O/oiqRykbK1qoXkVnn9c5iOuVEBXdsk6yu6kyI=";
      aarch64-linux = "sha256-pNi9qrfxM0OEPIwvpI8jiVQ/+nToc1i7mpsVWWBeZgs=";
    };

    vectorcraft = {
      version = "0.6.0";
      description = "Vector graphics editor";
      x86_64-linux = "sha256-SLWaHbWkVOmwbTuywitaAfhr5H6etDyMUQdoQHgD8fc=";
      aarch64-linux = "sha256-Zf1KJoXG+1tVqRyWjniFZDhxLyuzEwbqhnfnBq/xrFo=";
    };

    wordcraft = {
      version = "0.3.0";
      description = "Word processor";
      x86_64-linux = "sha256-wLOkthr+DoiRsThvc9yUrfUo2NhzYPP7cal7oDOBrsI=";
      aarch64-linux = "sha256-w72WTnPnzSxVap0OugSs1BrvrI28457HIjNgp9H7zTY=";
    };
  };

  info = apps.${app} or (throw "craft-apps: unknown app ${app}");
  system = stdenv.hostPlatform.system;
  arch = stdenv.hostPlatform.parsed.cpu.name;
in
stdenv.mkDerivation {
  pname = app;
  inherit (info) version;

  src = fetchurl {
    url = "https://github.com/storytold/${app}/releases/download/v${info.version}/${app}-${info.version}-linux-${arch}.tar.gz";
    hash = info.${system} or (throw "craft-apps: unsupported system ${system}");
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  # Only libc, libgcc and (for the audio apps) ALSA are linked. The windowing
  # and GPU stack is dlopened, so it has to land on RUNPATH or the app dies
  # at startup looking for a display backend.
  buildInputs = [
    alsa-lib
    stdenv.cc.cc.lib
  ];

  runtimeDependencies = [
    dbus
    libGL
    libx11
    libxcursor
    libxi
    libxcb
    libxkbcommon
    vulkan-loader
    wayland
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r bin share $out/

    runHook postInstall
  '';

  postFixup = lib.optionalString (info ? env) ''
    wrapProgram $out/bin/${app} ${
      lib.concatStringsSep " " (lib.mapAttrsToList (name: value: "--set ${name} ${value}") info.env)
    }
  '';

  meta = {
    inherit (info) description;
    homepage = "https://github.com/storytold/${app}";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = app;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
