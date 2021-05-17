{ pkgs ? import <nixpkgs> {} }:
let
  dev-setup = (builtins.readFile ./dev-setup);
in pkgs.mkShell {
  shellHook = "eval $(${dev-setup})";
}
