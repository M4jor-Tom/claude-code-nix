# claude-code-nix

Declarative [claude-code-bootstrap](https://github.com/SkYNewZ/claude-code-bootstrap)
for NixOS, as a home-manager module. Upstream is tracked as a git submodule.

## Usage

Add to your flake inputs — **`?submodules=1` is required** (templates live in a submodule):

```nix
inputs.claude-code-nix.url = "github:<you>/claude-code-nix?submodules=1";
```

Import the module in your home-manager config:

```nix
{
  imports = [ inputs.claude-code-nix.homeManagerModules.default ];
  programs.claudeBootstrap.enable = true;
  # options: language (default "English"), statusLine, rtk, plugins, personalClaudeMd
}
```

`programs.claudeBootstrap.enable = true` installs the CLI tools, writes `~/.claude/`
(CLAUDE.md, RTK.md, rules, skills, settings.json), and runs plugin/marketplace/MCP
setup on activation.

### Notes

- `claude-code` is unfree in nixpkgs. Set `nixpkgs.config.allowUnfree = true;`
  (or `nixpkgs.config.allowUnfreePredicate` scoped to just `claude-code`) in your own
  config, or the module won't build.
- Pre-existing unmanaged files in `~/.claude` (e.g. your own `skills/graphify`) will
  collide with home-manager. Set `home.backupFileExtension = "bak";` to let it back them up.
- `rtk = false` strips the RTK hooks from settings.json (matches upstream when rtk is absent).
- CLAUDE.md is upstream's; set `personalClaudeMd` to append your own block.

## Keeping it in sync

Run the `update-bootstrap-flake` skill from the repo, inside `nix develop` (which provides
`gh` and `git`). It checks upstream for new commits; if there are any, it syncs the
submodule, reconciles the module, and opens a PR. No new commits → it stops.
