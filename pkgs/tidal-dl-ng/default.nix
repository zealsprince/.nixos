{
  lib,
  python3,
  fetchurl,
  ffmpeg,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "tidal-dl-ng";
  version = "0.33.5";
  format = "wheel";

  # Packaged from the tidal-dl-ng-for-dj fork on PyPI. The original
  # (exislow/tidal-dl-ng) and the fork's GitHub repo were both taken down;
  # PyPI still serves the wheel and the hash pins it.
  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/00/70/7d15022dc5a3d7d142b66f55a5146f9fcded0d9792ed66f599c814dcc3d7/tidal_dl_ng_for_dj-${version}-py3-none-any.whl";
    sha256 = "130xm4dzvl35dxglfh4lkv9b7fwm3qkbk3affsqfvnys5rb033gh";
  };

  # Upstream pins tight version ranges; nixpkgs versions drift around them.
  pythonRelaxDeps = true;

  propagatedBuildInputs = with python3.pkgs; [
    ansi2html
    coloredlogs
    dataclasses-json
    m3u8
    mutagen
    pathvalidate
    pycryptodome
    python-ffmpeg
    requests
    rich
    tidalapi
    toml
    typer
  ];

  # ffmpeg for FLAC extraction and remuxing.
  makeWrapperArgs = [
    "--prefix PATH : ${lib.makeBinPath [ ffmpeg ]}"
  ];

  # The GUI entry points need the pyside6 extra, which isn't included here.
  postInstall = ''
    rm $out/bin/tdng $out/bin/tidal-dl-ng-gui
  '';

  meta = with lib; {
    description = "TIDAL media downloader, maintained fork of tidal-dl-ng";
    homepage = "https://pypi.org/project/tidal-dl-ng-for-dj/";
    license = licenses.agpl3Only;
    mainProgram = "tidal-dl-ng";
    platforms = platforms.all;
  };
}
