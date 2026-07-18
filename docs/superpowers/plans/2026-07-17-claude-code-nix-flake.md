# claude-code-nix Flake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A home-manager module (delivered as a flake) that declaratively reproduces SkYNewZ/claude-code-bootstrap on NixOS, plus a repo-local skill that opens a PR when upstream moves.

**Architecture:** Upstream is a git submodule at `upstream/`; the module reads its `templates/` at eval time and writes them into `~/.claude/` via `home.file`, builds `settings.json` in Nix, and runs the imperative plugin/MCP setup in a home-manager activation script. `flake.lock` pins only this repo's own inputs. A maintenance skill uses local git to detect upstream drift and open a PR.

**Tech Stack:** Nix flakes, home-manager, git submodules, `gh` CLI, Rust (`buildRustPackage` for `rtk`).

## Global Constraints

- `flake.lock` pins **only** `nixpkgs` and `home-manager` — never upstream. Upstream is tracked solely by the git submodule pointer.
- Consumers import with `?submodules=1` in the flake URL; without it `upstream/templates/` is empty and eval fails.
- `settings.json` transforms must match upstream `setup.sh` exactly: set `.language`; `del(.statusLine)` when statusLine disabled; `del(.hooks)` when rtk absent. Default `language = "English"` (override upstream's `"French"`).
- CLAUDE.md: **upstream wins**; `personalClaudeMd` option (default `""`) appends a personal block only if set.
- Module option namespace: `programs.claudeBootstrap`.
- Skills and rules are discovered dynamically via `builtins.readDir` so upstream additions need no code change; only structural changes (settings shape, new plugins/marketplaces, new top-level template files) need the maintenance skill.
- Supported systems: `x86_64-linux`, `aarch64-linux`.
- The activation script must guard on `command -v claude` and never fail the switch if claude is absent.

---

### Task 1: Repo scaffold, upstream submodule, flake with test harness  ✅ **DONE** (commits `3fcbd96..b355ffe`, review clean)

**Files:**
- Create: `flake.nix`
- Create: `examples/home.nix`
- Create: `.gitmodules` (via `git submodule add`)
- Create: `modules/claude-code.nix` (empty stub this task)

**Interfaces:**
- Produces: `homeManagerModules.default` (importable module), `checks.<system>.example` (a home-manager `activationPackage` importing the module), `packages.<system>.rtk`.

- [x] **Step 1: Add the upstream submodule**

```bash
cd /home/theta/repos/claude-code-nix
git submodule add https://github.com/SkYNewZ/claude-code-bootstrap upstream
git submodule update --init --recursive
ls upstream/templates/settings.json   # must exist
```

- [x] **Step 2: Create the empty module stub**

`modules/claude-code.nix`:

```nix
{ config, lib, ... }:
let cfg = config.programs.claudeBootstrap;
in {
  options.programs.claudeBootstrap.enable =
    lib.mkEnableOption "declarative claude-code-bootstrap setup";
  config = lib.mkIf cfg.enable { };
}
```

- [x] **Step 3: Create the example consumer config**

`examples/home.nix`:

```nix
{ ... }:
{
  home.username = "example";
  home.homeDirectory = "/home/example";
  home.stateVersion = "24.11";
  programs.claudeBootstrap.enable = true;
  # Keep checks fast/offline: don't build rtk in CI.
  programs.claudeBootstrap.rtk = false;
}
```

Note: `rtk` option does not exist yet (Task 5). It is set here now so later tasks don't need to touch this file; until Task 2 adds the option, temporarily comment the `rtk` line out. Uncomment it in Task 5.
For Task 1, comment out both `programs.claudeBootstrap.rtk` and leave only `enable`.

- [x] **Step 4: Write the flake**

`flake.nix`:

```nix
{
  description = "Declarative claude-code-bootstrap for home-manager (NixOS)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = nixpkgs.lib.genAttrs systems;
    in
    {
      homeManagerModules.default = import ./modules/claude-code.nix;

      packages = forAll (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in { rtk = pkgs.callPackage ./pkgs/rtk.nix { }; });

      # Tools the maintenance skill needs, guaranteed present via `nix develop`.
      devShells = forAll (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in { default = pkgs.mkShell { packages = [ pkgs.gh pkgs.git ]; }; });

      checks = forAll (system: {
        example = (home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [ self.homeManagerModules.default ./examples/home.nix ];
        }).activationPackage;
      });
    };
}
```

Note: the `devShells.default` output gives the maintenance skill (Task 7) `gh` and `git`
regardless of the host, so it can be run with `nix develop` on a minimal machine.

Note: `packages.rtk` references `./pkgs/rtk.nix`, created in Task 5. Until then, temporarily remove the `packages = ...;` block (or point it at a stub). Add a placeholder to keep the flake evaluable:

```nix
      # packages added in Task 5
```

Delete the `packages = forAll ...;` block for Task 1; re-add it in Task 5.

- [x] **Step 5: Verify the flake evaluates and the example builds**

Run:
```bash
nix flake check --no-build 2>&1 | tail -5
nix build .#checks.x86_64-linux.example --dry-run 2>&1 | tail -5
```
Expected: no evaluation errors. The dry-run lists derivations to build without failing.

- [x] **Step 6: Commit**

```bash
git add .gitmodules upstream flake.nix flake.lock modules/claude-code.nix examples/home.nix
git commit -m "feat: scaffold flake, upstream submodule, home-manager test harness"
```

---

### Task 2: Module options + CLI package installation  ✅ **DONE** (commits `b355ffe..9145226`, review clean)

**Files:**
- Modify: `modules/claude-code.nix`
- Modify: `examples/home.nix` (uncomment `rtk = false;`)

**Interfaces:**
- Produces options: `programs.claudeBootstrap.{enable, language, statusLine, rtk, plugins, personalClaudeMd}`.
- Produces: `config.home.packages` including ripgrep, fd, jq, yq-go, gh, glab, nodejs, bun, claude-code.

- [x] **Step 1: Replace the module stub with options + packages**

`modules/claude-code.nix`:

```nix
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
```

Note: `../pkgs/rtk.nix` does not exist until Task 5, but with `cfg.rtk = false` in the example it is never evaluated (`lib.optional false _` short-circuits). Keep the example's `rtk = false;`.

- [x] **Step 2: Uncomment the rtk line in the example**

In `examples/home.nix`, ensure this line is active:
```nix
  programs.claudeBootstrap.rtk = false;
```

- [x] **Step 3: Verify packages resolve**

Run:
```bash
nix eval --raw .#checks.x86_64-linux.example.drvPath >/dev/null && echo OK
nix eval --json --apply 'x: builtins.length x' \
  ".#homeManagerModules.default" 2>/dev/null || true
```
Primary check — build the example (packages must all exist in nixpkgs):
```bash
nix build .#checks.x86_64-linux.example --dry-run 2>&1 | tail -5
```
Expected: no "attribute 'X' missing" errors for any package (ripgrep, fd, jq, yq-go, gh, glab, nodejs, bun, claude-code all exist in nixpkgs-unstable).

- [x] **Step 4: Commit**

```bash
git add modules/claude-code.nix examples/home.nix
git commit -m "feat: module options and CLI package installation"
```

---

### Task 3: Deploy templates and skills into ~/.claude  ✅ **DONE** (commits `9145226..a50cbf5`, review clean)

**Files:**
- Modify: `modules/claude-code.nix`

**Interfaces:**
- Consumes: `cfg.personalClaudeMd`.
- Produces: `config.home.file` entries for `.claude/CLAUDE.md`, `.claude/RTK.md`, `.claude/conventional-commits.md`, `.claude/rules/context7.md`, and one entry per skill dir under `.claude/skills/`.

- [x] **Step 1: Add file-deployment logic to the module**

Insert these `let` bindings (after `cfg = ...;`):

```nix
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
```

Add to the `config` block (keep the existing `home.packages`):

```nix
    home.file = skillFiles // {
      ".claude/CLAUDE.md".source = claudeMdSource;
      ".claude/RTK.md".source = "${templates}/RTK.md";
      ".claude/conventional-commits.md".source = "${templates}/conventional-commits.md";
      ".claude/rules/context7.md".source = "${templates}/rules/context7.md";
    };
```

- [x] **Step 2: Verify the file set is generated from the submodule**

Run:
```bash
nix eval --json .#checks.x86_64-linux.example.drvPath >/dev/null && echo BUILDS
nix eval --json \
  --apply 'cfg: builtins.attrNames cfg.config.home.file' \
  '.#homeConfigurations' 2>/dev/null || true
```
Primary check — dry build must resolve every `source` path (proves submodule files are present under `?submodules` eval):
```bash
nix build '.?submodules=1#checks.x86_64-linux.example' --dry-run 2>&1 | tail -5
```
Expected: no "path does not exist" errors for any `${templates}/...` source. `skillNames` non-empty (graphify, llm-council, markitdown, playwright-cli, prd, writing-adrs).

- [x] **Step 3: Commit**

```bash
git add modules/claude-code.nix
git commit -m "feat: deploy CLAUDE.md, rules, and skills from upstream submodule"
```

---

### Task 4: Build settings.json with upstream's conditional transforms  ✅ **DONE** (commits `a50cbf5..9acf2c8`, review clean)

**Files:**
- Modify: `modules/claude-code.nix`

**Interfaces:**
- Consumes: `cfg.language`, `cfg.statusLine`, `cfg.rtk`.
- Produces: `config.home.file.".claude/settings.json"`.

- [x] **Step 1: Add the settings builder**

Add to the `let` bindings:

```nix
  baseSettings = builtins.fromJSON (builtins.readFile "${templates}/settings.json");
  settings =
    let
      s0 = baseSettings // { language = cfg.language; };
      s1 = if cfg.statusLine then s0 else builtins.removeAttrs s0 [ "statusLine" ];
      s2 = if cfg.rtk then s1 else builtins.removeAttrs s1 [ "hooks" ];
    in s2;
  settingsFile = (pkgs.formats.json { }).generate "claude-settings.json" settings;
```

Add to the `home.file` attrset:

```nix
      ".claude/settings.json".source = settingsFile;
```

- [x] **Step 2: Verify the transforms**

Run (language override + hooks/statusLine presence):
```bash
nix eval --json --apply '
  let m = import ./modules/claude-code.nix; in
  "read-manually"' 2>/dev/null || true

nix build '.?submodules=1#checks.x86_64-linux.example' -o result-check
jq '.language, (.hooks|type), (.statusLine|type)' \
  $(readlink -f result-check)/home-files/.claude/settings.json
```
Expected: `"English"`, then `"null"` (hooks deleted because example sets `rtk = false`), then `"object"` (statusLine kept). If the `home-files` path differs, locate it: `find $(readlink -f result-check) -name settings.json`.

- [x] **Step 3: Verify rtk=true keeps hooks (temporary toggle)**

Run:
```bash
nix build '.?submodules=1#checks.x86_64-linux.example' \
  --override-input nixpkgs nixpkgs 2>/dev/null || true
# Manual assert of the transform without building rtk:
nix eval --impure --expr '
  let
    pkgs = import <nixpkgs> {};
    base = builtins.fromJSON (builtins.readFile ./upstream/templates/settings.json);
    withRtk = base;                       # rtk=true keeps hooks
    withoutRtk = builtins.removeAttrs base [ "hooks" ];
  in { withHooks = withRtk ? hooks; withoutHooks = withoutRtk ? hooks; }
' 2>&1 | tail -3
```
Expected: `{ withHooks = true; withoutHooks = false; }`.

- [x] **Step 4: Commit**

```bash
git add modules/claude-code.nix
git commit -m "feat: build settings.json with language/statusLine/rtk transforms"
```

---

### Task 5: Package rtk and wire the rtk option  ✅ **DONE** (commits `9acf2c8..4ecdfdf`, review clean)

**Files:**
- Create: `pkgs/rtk.nix`
- Modify: `flake.nix` (re-add the `packages` output)

**Interfaces:**
- Produces: `packages.<system>.rtk`; consumed by the module's `home.packages` when `cfg.rtk = true`.

- [x] **Step 1: Discover rtk's source**

`rtk` = "Rust Token Killer". Find how upstream installs it and where the source lives:
```bash
grep -n -i "rtk" upstream/setup.sh
```
Look for a `cargo install <name>`, a `brew install <formula>` (inspect the formula's `homepage`/`url`), or a GitHub release URL. Record: crate name (if on crates.io) OR GitHub `owner/repo` + a release tag.

- [x] **Step 2: Write the derivation (crates.io form)**

If rtk is a published crate, `pkgs/rtk.nix`:

```nix
{ rustPlatform, fetchCrate, lib }:
rustPlatform.buildRustPackage rec {
  pname = "rtk";
  version = "REPLACE_WITH_VERSION_FROM_STEP_1";

  src = fetchCrate {
    inherit pname version;
    hash = lib.fakeHash;          # replaced in Step 3
  };

  cargoHash = lib.fakeHash;       # replaced in Step 3

  meta = {
    description = "Rust Token Killer - token optimization hook for Claude Code";
    mainProgram = "rtk";
  };
}
```

If it is a GitHub source instead, swap `src` for:
```nix
  src = fetchFromGitHub {
    owner = "OWNER"; repo = "rtk"; rev = "vVERSION"; hash = lib.fakeHash;
  };
```
(and add `fetchFromGitHub` to the function args).

- [x] **Step 3: Resolve the hashes**

Nix reports the correct hash when given a fake one. Iterate:
```bash
nix build .#packages.x86_64-linux.rtk 2>&1 | grep -A2 "hash mismatch"
```
Copy the `got:` hash into `src.hash`, rebuild, then copy the next `got:` into `cargoHash`. Rebuild until it compiles.
Expected final: `nix build .#packages.x86_64-linux.rtk` succeeds and `./result/bin/rtk --version` runs.

- [x] **Step 4: Re-add the packages output to flake.nix**

Restore inside `outputs` (removed in Task 1):
```nix
      packages = forAll (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in { rtk = pkgs.callPackage ./pkgs/rtk.nix { }; });
```

- [x] **Step 5: Verify the module builds rtk when enabled**

Run:
```bash
nix build .#packages.x86_64-linux.rtk && ./result/bin/rtk --version
```
Expected: builds and prints a version.
Note: leave `examples/home.nix` at `rtk = false;` so `nix flake check` stays fast; rtk is verified via the `packages` output directly.

- [x] **Step 6: Commit**

```bash
git add pkgs/rtk.nix flake.nix
git commit -m "feat: package rtk (Rust Token Killer)"
```

If rtk cannot be packaged reasonably, stop and report: the fallback (`rtk = false` → hooks stripped) already works, so ship without it and note it in the README.

---

### Task 6: Activation script for plugins, marketplaces, and MCP  ✅ **DONE** (commits `4ecdfdf..a74e103`, review clean)

**Files:**
- Modify: `modules/claude-code.nix`

**Interfaces:**
- Consumes: `cfg.plugins`.
- Produces: `config.home.activation.claudeBootstrap`.

- [x] **Step 1: Add the marketplace/plugin/MCP data and activation script**

Add to the `let` bindings:

```nix
  marketplaces = [
    "anthropics/claude-plugins-official"
    "thedotmack/claude-mem"
    "nextlevelbuilder/ui-ux-pro-max-skill"
    "Egonex-AI/Understand-Anything"
    "DietrichGebert/ponytail"
  ];
  plugins = [
    "superpowers@claude-plugins-official"
    "frontend-design@claude-plugins-official"
    "claude-md-management@claude-plugins-official"
    "claude-mem@thedotmack"
    "ui-ux-pro-max@ui-ux-pro-max-skill"
    "understand-anything@understand-anything"
    "ponytail@ponytail"
  ];
  mktLines = pre: xs: lib.concatMapStringsSep "\n" (x: "  claude ${pre} ${x} || true") xs;
```

Add to the `config` block:

```nix
    home.activation.claudeBootstrap = lib.mkIf cfg.plugins (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if command -v claude >/dev/null 2>&1; then
        ${mktLines "plugin marketplace add" marketplaces}
        ${mktLines "plugin install" plugins}
          claude mcp add --transport http context7 https://mcp.context7.com/mcp --scope user || true
        else
          echo "claudeBootstrap: 'claude' not on PATH; skipping plugin/MCP setup" >&2
        fi
      ''
    );
```

- [x] **Step 2: Verify the activation script content**

Run:
```bash
nix build '.?submodules=1#checks.x86_64-linux.example' -o result-check
grep -c "claude plugin marketplace add" result-check/activate
grep -c "claude plugin install" result-check/activate
grep -c "claude mcp add --transport http context7" result-check/activate
grep -c "command -v claude" result-check/activate
```
Expected: `5`, `7`, `1`, `1`. (If the generated file is not `activate`, find it: `grep -rl "context7" result-check`.)

- [x] **Step 3: Commit**

```bash
git add modules/claude-code.nix
git commit -m "feat: activation script for plugins, marketplaces, and context7 MCP"
```

---

### Task 7: Maintenance skill (detect upstream drift, open PR)

**Files:**
- Create: `.claude/skills/update-bootstrap-flake/SKILL.md`

**Interfaces:**
- Consumes: the `upstream/` submodule and `gh` CLI. Standalone; nothing depends on it.

- [ ] **Step 1: Write the skill**

`.claude/skills/update-bootstrap-flake/SKILL.md`:

````markdown
---
name: update-bootstrap-flake
description: Use to check whether SkYNewZ/claude-code-bootstrap has new commits and, if so, sync the submodule, reconcile the module, and open a PR on claude-code-nix.
---

# Update claude-code-bootstrap flake

Run from the repo root, inside the flake's devshell so `gh` and `git` are guaranteed
present: `nix develop` (or prefix commands with `nix develop -c`). All state lives in
the `upstream/` git submodule pointer.

## 1. Detect drift

```bash
git submodule update --init upstream
OLD=$(git -C upstream rev-parse HEAD)
git -C upstream fetch --quiet origin
NEW=$(git -C upstream rev-parse origin/HEAD 2>/dev/null || git -C upstream rev-parse origin/main)
echo "old=$OLD new=$NEW"
```

If `OLD == NEW`: **stop.** Report "claude-code-bootstrap is up to date ($OLD)." Do nothing else.

## 2. Classify what changed

```bash
git -C upstream diff --name-status "$OLD" "$NEW" -- templates/ setup.sh
```

Map each change against `modules/claude-code.nix`:

| Upstream change | Module action |
|---|---|
| New/removed dir under `templates/skills/` | None — `skillNames` reads the dir dynamically. |
| New/removed file under `templates/rules/` | None if referenced dynamically; else add/remove the `home.file` entry. |
| New top-level `templates/*.md` | Add a `home.file.".claude/<file>".source` entry. |
| `templates/settings.json` keys added/removed/reshaped | Update the settings builder if a transformed key (language/statusLine/hooks) moved; otherwise no change (whole file is passed through). |
| `MARKETPLACES` array changed in `setup.sh` | Update the `marketplaces` list in the module. |
| `PLUGINS` array changed in `setup.sh` | Update the `plugins` list. |
| New `claude mcp add ...` in `setup.sh` | Add the command to the activation script. |
| New install step / new CLI tool | Add the package to `home.packages`. |

**Anything you cannot confidently classify: do NOT edit. Record it under "Needs review" in the PR body.**

## 3. Apply and verify

Move the pointer and apply classified edits:
```bash
git submodule update --remote upstream
# ...edit modules/claude-code.nix per the table...
nix build '.?submodules=1#checks.x86_64-linux.example' --dry-run
```
The dry build must succeed before opening a PR.

## 4. Open the PR

```bash
SHORT=$(git -C upstream rev-parse --short HEAD)
git checkout -b "update-upstream-$SHORT"
git add upstream modules/claude-code.nix
git commit -m "chore: sync claude-code-bootstrap to $SHORT"
gh pr create --fill --title "Sync claude-code-bootstrap ($SHORT)" \
  --body "Bumps the upstream submodule $OLD -> $NEW.

## Classified changes
<list what you applied>

## Needs review
<list anything you could not classify, or 'none'>"
```

## Dry-run mode

If invoked with "dry run": perform steps 1–2 only, print the classification table result and planned edits, and make no commits, submodule moves, or PR.
````

- [ ] **Step 2: Verify the detect logic runs and reports up-to-date**

Run:
```bash
git -C upstream fetch --quiet origin
OLD=$(git -C upstream rev-parse HEAD)
NEW=$(git -C upstream rev-parse origin/HEAD 2>/dev/null || git -C upstream rev-parse origin/main)
[ "$OLD" = "$NEW" ] && echo "UP TO DATE" || echo "DRIFT: $OLD -> $NEW"
```
Expected: `UP TO DATE` immediately after Task 1's submodule init (or `DRIFT` if upstream moved since — both are correct outputs).

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/update-bootstrap-flake/SKILL.md
git commit -m "feat: maintenance skill to sync upstream and open PR"
```

---

### Task 8: README and final flake check

**Files:**
- Create: `README.md`

**Interfaces:**
- None (documentation).

- [ ] **Step 1: Write the README**

`README.md`:

````markdown
# claude-code-nix

Declarative [claude-code-bootstrap](https://github.com/SkYNewZ/claude-code-bootstrap)
for NixOS, as a home-manager module. Upstream is tracked as a git submodule.

## Usage

Add to your flake inputs — **`?submodules=1` is required** (templates live in a submodule):

```nix
inputs.claude-code-nix.url = "git+https://github.com/<you>/claude-code-nix?submodules=1";
# NOTE: git+https, NOT github: — the github: tarball fetcher omits submodules.
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

- Pre-existing unmanaged files in `~/.claude` (e.g. your own `skills/graphify`) will
  collide with home-manager. Set `home.backupFileExtension = "bak";` to let it back them up.
- `rtk = false` strips the RTK hooks from settings.json (matches upstream when rtk is absent).
- CLAUDE.md is upstream's; set `personalClaudeMd` to append your own block.

## Keeping it in sync

Run the `update-bootstrap-flake` skill from the repo, inside `nix develop` (which provides
`gh` and `git`). It checks upstream for new commits; if there are any, it syncs the
submodule, reconciles the module, and opens a PR. No new commits → it stops.
````

- [ ] **Step 2: Full flake check**

Run:
```bash
nix flake check '.?submodules=1' 2>&1 | tail -10
nix build '.?submodules=1#checks.x86_64-linux.example' && echo BUILD_OK
```
Expected: no errors; `BUILD_OK`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: README with usage and sync instructions"
```

---

## Post-implementation (manual, by the user)

1. Create the GitHub repo and add it as `origin` (needed for the skill's `gh pr create`).
2. `git push -u origin main` (submodule is pushed by reference — the `.gitmodules` + pointer travel with it).
3. Import into your real home-manager config with `?submodules=1` and switch.
