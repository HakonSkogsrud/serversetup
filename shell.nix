{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  packages = with pkgs; [
    ansible
    ansible-lint
    ansible-language-server
    basedpyright
    pre-commit
    ruff
    yamllint
    python3Packages.passlib
  ];

  shellHook = ''
    export ANSIBLE_CONFIG="$PWD/ansible.cfg"
  '';
}