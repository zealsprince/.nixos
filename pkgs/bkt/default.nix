{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "bkt";
  version = "0.28.2";

  src = fetchFromGitHub {
    owner = "avivsinai";
    repo = "bitbucket-cli";
    tag = "v${version}";
    hash = "sha256-aoEXstV0Newb0lEDaVjkXb4Z42U/jpLfnOmwGALagZk=";
  };

  vendorHash = "sha256-1PJ8hqO7+WN4gQXQT2aNT6tciNjEi5utD97UOJKA5oI=";

  subPackages = [ "cmd/bkt" ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/avivsinai/bitbucket-cli/internal/build.versionFromLdflags=${version}"
  ];

  meta = with lib; {
    description = "Bitbucket CLI with gh-like ergonomics, targets Bitbucket Cloud and Data Center";
    homepage = "https://github.com/avivsinai/bitbucket-cli";
    license = licenses.mit;
    mainProgram = "bkt";
    platforms = platforms.unix;
  };
}
