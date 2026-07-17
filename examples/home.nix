{ ... }:
{
  home.username = "example";
  home.homeDirectory = "/home/example";
  home.stateVersion = "24.11";
  programs.claudeBootstrap.enable = true;
  # Keep checks fast/offline: don't build rtk in CI.
  programs.claudeBootstrap.rtk = false;
}
