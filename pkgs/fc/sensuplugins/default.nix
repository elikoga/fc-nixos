{ pkgs, libyaml, python3Packages }:

let
  py = python3Packages;

in
  py.buildPythonApplication rec {
    name = "fc-sensuplugins-${version}";
    version = "1.0";
    src = ./.;
    dontStrip = true;
    propagatedBuildInputs = [
      libyaml
      py.nagiosplugin
      py.requests
      py.psutil
      py.pyyaml
    ];
  }
