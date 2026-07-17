{ config, lib, pkgs, ... }:
let
  cfg = config.programs.claudeBootstrap;
in {
  options.programs.claudeBootstrap = {
    enable = lib.mkEnableOption "declarative claude-code-bootstrap setup";

    language = lib.mkOption {
      type = lib.types.str;
      default = "English";
      description = "Value written to settings.json .language (upstream default is French).";
    };

    statusLine = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Keep the ccstatusline statusLine block in settings.json.";
    };

    rtk = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install rtk and keep the RTK PreToolUse hooks. If false, hooks are stripped (matches upstream when rtk absent).";
    };

    plugins = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run the plugin/marketplace/MCP activation commands.";
    };

    personalClaudeMd = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Optional personal block appended to upstream's CLAUDE.md. Empty = pure upstream.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = (with pkgs; [
      ripgrep fd jq yq-go gh glab nodejs bun claude-code
    ]) ++ lib.optional cfg.rtk (pkgs.callPackage ../pkgs/rtk.nix { });
  };
}
