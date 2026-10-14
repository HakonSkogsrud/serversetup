{ pkgs, lib, ... }:
{
  home.username = "haaksk";
  # Fedora Atomic's /home is a symlink; use the account's real home path.
  home.homeDirectory = "/var/home/haaksk";
  home.stateVersion = "26.05";
  targets.genericLinux.enable = true;
  # Editors are host RPMs; the Nix environment currently contains CLI tools only.
  targets.genericLinux.gpu.enable = false;
  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    eza ripgrep zoxide fzf fd bat lazygit neovim uv tmux
    zsh-autosuggestions nerd-fonts.jetbrains-mono
  ];
  fonts.fontconfig.enable = true;
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # The image supplies /usr/bin/zsh. Preserve the existing custom dotfile,
  # substituting the plugin's actual Nix store path.
  home.file.".zshrc".text = lib.replaceStrings
    [ "@autosuggestions@" ]
    [ "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]
    (builtins.readFile ./dotfiles/zshrc);
  home.file.".tmux.conf".source = ./dotfiles/tmux.conf;
  home.file.".config/lazygit/config.yml".source = ./dotfiles/lazygit.yml;
}
