{ pkgs ? import <nixpkgs> {} }:
  pkgs.mkShell {
    shellHook = (builtins.readFile ./dev-setup);
}
