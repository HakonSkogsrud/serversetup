let
  pkgs = import <nixpkgs> { };
in
pkgs.mkShellNoCC {
  pagkages = with pkgs; [
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
