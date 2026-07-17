{ config, lib, ... }:
let cfg = config.programs.claudeBootstrap;
in {
  options.programs.claudeBootstrap.enable =
    lib.mkEnableOption "declarative claude-code-bootstrap setup";
  config = lib.mkIf cfg.enable { };
}
