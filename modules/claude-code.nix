{ config, lib, pkgs, ... }:
let
  cfg = config.programs.claudeBootstrap;

  upstream = ../upstream;
  templates = "${upstream}/templates";

  # Discover skills dynamically so upstream additions need no code change.
  skillNames = builtins.attrNames (builtins.readDir "${templates}/skills");
  skillFiles = lib.listToAttrs (map (name: {
    name = ".claude/skills/${name}";
    value = { source = "${templates}/skills/${name}"; recursive = true; };
  }) skillNames);

  claudeMdSource =
    if cfg.personalClaudeMd == ""
    then "${templates}/CLAUDE.md"
    else pkgs.writeText "CLAUDE.md"
      (builtins.readFile "${templates}/CLAUDE.md" + "\n\n" + cfg.personalClaudeMd);

  baseSettings = builtins.fromJSON (builtins.readFile "${templates}/settings.json");
  settings =
    let
      s0 = baseSettings // { language = cfg.language; };
      s1 = if cfg.statusLine then s0 else builtins.removeAttrs s0 [ "statusLine" ];
      s2 = if cfg.rtk then s1 else builtins.removeAttrs s1 [ "hooks" ];
    in s2;
  settingsFile = (pkgs.formats.json { }).generate "claude-settings.json" settings;
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

    home.file = skillFiles // {
      ".claude/CLAUDE.md".source = claudeMdSource;
      ".claude/RTK.md".source = "${templates}/RTK.md";
      ".claude/conventional-commits.md".source = "${templates}/conventional-commits.md";
      ".claude/rules/context7.md".source = "${templates}/rules/context7.md";
      ".claude/settings.json".source = settingsFile;
    };
  };
}
