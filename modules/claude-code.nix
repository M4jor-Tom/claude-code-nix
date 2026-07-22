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
in {
  options.programs.claudeBootstrap = {
    enable = lib.mkEnableOption "declarative claude-code-bootstrap setup";

    rtk = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the rtk CLI token-saving proxy (adds it to home.packages). settings.json is verbatim from overrides/, so this no longer alters it.";
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
      ".claude/settings.json".source = ../overrides/settings.json;
    };

    # Plugins/marketplaces are user state (claude plugin ...), declared in
    # overrides/settings.json .enabledPlugins — not managed here. This only
    # registers the context7 MCP endpoint.
    home.activation.claudeBootstrap =
      lib.hm.dag.entryAfter [ "installPackages" ] ''
        export PATH="${config.home.profileDirectory}/bin:$PATH"
        if command -v claude >/dev/null 2>&1; then
          claude mcp add --transport http context7 https://mcp.context7.com/mcp --scope user || true
        else
          echo "claudeBootstrap: 'claude' not on PATH; skipping MCP setup" >&2
        fi
      '';

    assertions = [{
      assertion = builtins.pathExists "${templates}/settings.json";
      message = "claudeBootstrap: upstream/ submodule is empty. Import this flake with '?submodules=1' in the URL (e.g. github:you/claude-code-nix?submodules=1).";
    }];
  };
}
