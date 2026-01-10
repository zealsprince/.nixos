{ config, pkgs, lib, ... }:

let
  terraposh = pkgs.stdenvNoCC.mkDerivation {
    pname = "terraposh";
    version = "0-unstable-2025-05-10";

    src = pkgs.fetchFromGitHub {
      owner = "smastrorocco";
      repo = "terraposh";
      rev = "master";
      sha256 = "sha256-1/ZH53wDIdWrvHbrQkjMt5tXEqdFemxzPeidqNZ0mfw=";
    };

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      # Install as a PowerShell module
      mkdir -p $out/share/powershell/Modules/terraposh
      cp -r ./* $out/share/powershell/Modules/terraposh/

      runHook postInstall
    '';
  };
in
{
  # Install PowerShell itself
  home.packages = [ pkgs.powershell ];

  # Configure the profile manually via XDG config
  # PowerShell on Linux looks for the profile at ~/.config/powershell/Microsoft.PowerShell_profile.ps1
  xdg.configFile."powershell/Microsoft.PowerShell_profile.ps1".text = ''
    # Add terraposh to PSModulePath
    $env:PSModulePath = $env:PSModulePath + [IO.Path]::PathSeparator + "${terraposh}/share/powershell/Modules"

    # Auto-import it
    Import-Module terraposh -ErrorAction SilentlyContinue
  '';
}
