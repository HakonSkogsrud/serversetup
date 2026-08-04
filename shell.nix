{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  packages = with pkgs; [
    ansible
    ansible-lint
    ansible-language-server
    pre-commit
    yamllint
    python3Packages.passlib
  ];

  shellHook = ''
    export ANSIBLE_CONFIG="$PWD/ansible.cfg"
  '';
}