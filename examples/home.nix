{ ... }:
{
  home.username = "example";
  home.homeDirectory = "/home/example";
  home.stateVersion = "24.11";
  programs.claudeBootstrap.enable = true;
  # Keep checks fast/offline: don't build rtk in CI.
  # rtk option does not exist until Task 2; uncomment in Task 5.
  # programs.claudeBootstrap.rtk = false;
}
