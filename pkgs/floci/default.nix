{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  installShellFiles,
  zlib,
}:

let
  version = "0.2.3";

  # Upstream publishes GraalVM native images per platform. The hashes are the
  # release's sha256sums.txt converted to SRI.
  platforms = {
    x86_64-linux = {
      asset = "floci-linux-amd64";
      hash = "sha256-9FkC2yofCbmZAEhkkGXoQkMy25wP3OeAUpGSoBn7d8I=";
    };
    aarch64-linux = {
      asset = "floci-linux-arm64";
      hash = "sha256-HBV4rjvYoNPoM92QBJNO2A9yQTwsakxIxCPRxWNKuwA=";
    };
    aarch64-darwin = {
      asset = "floci-darwin-arm64";
      hash = "sha256-CyNsoLwc1cGAPqsccPoGiIlPwK1/tUsssIebQ6Sr6CM=";
    };
    x86_64-darwin = {
      asset = "floci-darwin-amd64";
      hash = "sha256-h9NKNtrKSINma6LztuZMucc2THgu/1PRnob+lWSrQWQ=";
    };
  };

  platform =
    platforms.${stdenv.hostPlatform.system}
      or (throw "floci: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "floci";
  inherit version;

  src = fetchurl {
    url = "https://github.com/floci-io/floci-cli/releases/download/${version}/${platform.asset}";
    inherit (platform) hash;
  };

  dontUnpack = true;

  nativeBuildInputs = [ installShellFiles ] ++ lib.optional stdenv.hostPlatform.isLinux autoPatchelfHook;

  # The Linux binary only links glibc and zlib.
  buildInputs = lib.optional stdenv.hostPlatform.isLinux zlib;

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/bin/floci

    runHook postInstall
  '';

  # Completions come from the binary itself, so only generate them when the
  # build can run it. autoPatchelfHook normally runs in fixup, after this, so
  # patch early or the binary can't find its interpreter.
  #
  # Bash only: `completion zsh` prints the same picocli bash script, which zsh
  # can only use through bashcompinit, not as a _floci function on fpath.
  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    ${lib.optionalString stdenv.hostPlatform.isLinux "autoPatchelf $out/bin"}

    installShellCompletion --cmd floci \
      --bash <(HOME=$TMPDIR $out/bin/floci completion bash)
  '';

  meta = {
    description = "CLI for the Floci local cloud emulators (AWS, GCP, Azure, OCI)";
    homepage = "https://github.com/floci-io/floci-cli";
    license = lib.licenses.mit;
    mainProgram = "floci";
    platforms = builtins.attrNames platforms;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
