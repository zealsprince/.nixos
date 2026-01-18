{
  lib,
  python3,
  fetchurl,
}:

python3.pkgs.buildPythonApplication {
  pname = "campdown";
  version = "1.49";
  format = "wheel";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/e2/07/52181cd248529f7ba563f98e617c756d133c52f3840392d0c7c8be61a557/campdown-1.49-py3-none-any.whl";
    sha256 = "a0ab8dd1a3f6c7e2e320b61ffd28b77eb3e2ddc6bfcff991374a00fa66f0ee04";
  };

  propagatedBuildInputs = with python3.pkgs; [
    requests
    mutagen
    docopt
  ];

  meta = with lib; {
    description = "Bandcamp track and album downloader";
    homepage = "https://github.com/catlinman/campdown";
    license = licenses.mit;
    mainProgram = "campdown";
    platforms = platforms.all;
  };
}
