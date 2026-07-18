# claude-code-nix

Declarative [claude-code-bootstrap](https://github.com/SkYNewZ/claude-code-bootstrap)
for NixOS, as a home-manager module. Upstream is tracked as a git submodule.

## Usage

Add to your flake inputs. Templates live in a git submodule, so you **must** use the
`git+https` (or `git+ssh`) scheme with `?submodules=1` — the `github:` scheme fetches a
tarball that omits submodules, leaving `upstream/templates/` empty and failing eval:

```nix
inputs.claude-code-nix.url = "git+https://github.com/<you>/claude-code-nix?submodules=1";
```

(For a private repo use `git+ssh://git@github.com/<you>/claude-code-nix?submodules=1`.)

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
- **If you have used Claude Code before**, you already have `~/.claude/settings.json`,
  `~/.claude/CLAUDE.md`, and possibly your own `~/.claude/skills/*` — home-manager will
  **abort the entire first switch** on these unmanaged files unless you set
  `home.backupFileExtension = "bak";` (which moves them aside). This is effectively
  required, not optional.
- The plugin/marketplace/MCP setup runs on **every** `home-manager switch` (≈13 `claude`
  network calls: it installs third-party marketplace plugins and registers the context7
  MCP endpoint). It's idempotent and non-fatal, but if you don't want it, set
  `programs.claudeBootstrap.plugins = false;`.
- `rtk = false` strips the RTK hooks from settings.json (matches upstream when rtk is absent).
- CLAUDE.md is upstream's; set `personalClaudeMd` to append your own block.

## Keeping it in sync

Run the `update-bootstrap-flake` skill from the repo, inside `nix develop` (which provides
`gh` and `git`). It checks upstream for new commits; if there are any, it syncs the
submodule, reconciles the module, and opens a PR. No new commits → it stops.
