# claude-code-nix — Design

**Date:** 2026-07-17
**Status:** Approved (pending spec review)

## Goal

Replicate what [SkYNewZ/claude-code-bootstrap](https://github.com/SkYNewZ/claude-code-bootstrap)
does — a shell script that sets up a Claude Code environment — but declaratively
for NixOS, delivered as a **home-manager module** in a flake. Plus a mechanism to
keep the flake in sync when the upstream (Nix-free) repo changes.

## Non-goals

- Reproducing upstream's `curl | bash` installers for claude-code/bun (Nix provides these).
- Reproducing upstream's shell-RC `PATH` edits (home-manager owns PATH).
- A general-purpose Claude Code Nix module for arbitrary configs — this mirrors *this*
  bootstrap, faithfully.

## Decisions (locked)

| Question | Decision |
|---|---|
| Consumer's Nix setup | Flakes + home-manager → ship a home-manager module. |
| Managed scope | Everything: CLI tools, skills, settings.json + rules, plugins + MCP. |
| `~/.claude/CLAUDE.md` | **Upstream wins** (full ownership). A commented, default-off "personal block" knob left in the module to re-add graphify/email later. |
| How upstream content reaches the flake | **git submodule** at `upstream/`. No vendoring, no Nix pin. |
| Upstream commit tracking | The submodule pointer itself (git-native). `flake.lock` pins only this repo's own inputs. |
| Update mechanism | A repo-local Claude Code **skill** using local git commands; opens a PR on change. |
| Language (`settings.json`) | **English** (override upstream's French). |
| Prereqs accepted | `?submodules=1` in the flake URL; a GitHub remote for the skill's PRs. |

## Architecture

```
claude-code-nix/
├── flake.nix                 # outputs.homeManagerModules.default; inputs: nixpkgs, home-manager
├── flake.lock                # this repo's inputs only — nothing upstream
├── .gitmodules               # upstream = SkYNewZ/claude-code-bootstrap
├── upstream/                  # git submodule (the bootstrap repo). Pointer = tracked commit.
├── modules/claude-code.nix    # the home-manager module; reads ${self}/upstream/templates/…
├── pkgs/rtk.nix               # buildRustPackage for rtk (optional; see Components)
├── .claude/skills/update-bootstrap-flake/SKILL.md
└── docs/superpowers/specs/…
```

**Data flow:** upstream templates live in the submodule → `modules/claude-code.nix`
reads them at eval time from the flake source tree → home-manager writes/symlinks them
into `~/.claude/` and runs an activation script for the imperative bits.

**Submodules caveat (accepted):** consuming the flake requires the `git+https` (or
`git+ssh`) scheme with `?submodules=1`:
`inputs.claude-code-nix.url = "git+https://github.com/<you>/claude-code-nix?submodules=1";`.
The `github:` scheme fetches a tarball that omits submodules, so `upstream/templates/`
would be empty and evaluation fails.

## Components

### 1. `flake.nix`
- Inputs: `nixpkgs`, `home-manager` (follows nixpkgs). No upstream input.
- Output: `homeManagerModules.default = import ./modules/claude-code.nix;`
- Optional convenience output: `packages.<system>.rtk` from `pkgs/rtk.nix`.

### 2. `modules/claude-code.nix` (home-manager module)
Option namespace: `programs.claudeBootstrap`. Single toggle `enable`, plus a few knobs
(see below). When enabled it mirrors the bootstrap:

| Bootstrap action | Nix translation |
|---|---|
| Install ripgrep, fd, jq, yq, gh, glab, node, bun, claude-code | `home.packages` from nixpkgs |
| `rtk` (Rust Token Killer) | `pkgs/rtk.nix` (`buildRustPackage`). If the build is disabled/unavailable, **strip the RTK hooks from settings.json — exactly as upstream does when rtk is absent.** |
| Copy `templates/{CLAUDE.md,RTK.md,conventional-commits.md,rules/context7.md}` | `home.file.".claude/…".source = "${./upstream}/templates/…"` (read-only symlinks) |
| Copy `templates/skills/*` | recursive `home.file` from `${./upstream}/templates/skills/` |
| Generate `settings.json` via jq | Built in Nix from `templates/settings.json` applying the same conditionals: language (→ **English**), statusLine include/exclude, RTK-hooks include only if rtk present |
| `claude plugin marketplace add …` + activate plugins | `home.activation` script running the same **idempotent** `claude` commands |
| `claude mcp add context7 …` (keyless HTTP) | `home.activation` (idempotent) |

**Knobs (module options):**
- `enable` (bool)
- `language` (str, default `"English"`)
- `statusLine` (bool, default true)
- `rtk` (bool, default true → build+use rtk and keep hooks; false → strip hooks)
- `plugins` (bool, default true → run marketplace/plugin activation)
- `personalClaudeMd` (str, default `""`) — appended to CLAUDE.md if non-empty; the
  "personal block" knob, default off so upstream wins.

**Activation-script note:** plugin/marketplace/MCP setup is imperative state in
`~/.claude.json` / `~/.claude/plugins/`. The upstream `claude` subcommands are
idempotent, so the activation script re-runs them safely on each home-manager switch.
It guards on `claude` being on PATH.

### 3. `pkgs/rtk.nix`
`buildRustPackage` for `rtk` (Rust Token Killer). Exact upstream source to be resolved
during implementation from how the bootstrap installs it (brew/cargo). If packaging
proves painful, fallback is `rtk = false` → hooks stripped, no hard failure.

### 4. `.claude/skills/update-bootstrap-flake/SKILL.md` (maintenance skill)
Invoked manually. All local git; no Nix pin involved. Steps:

1. Ensure submodule present: `git submodule update --init upstream`.
2. Current pin: `git -C upstream rev-parse HEAD`.
3. Fetch latest: `git -C upstream fetch --quiet` → `git -C upstream rev-parse origin/HEAD`
   (resolve upstream default branch).
4. **Equal → stop** and report "up to date."
5. **Different →**
   a. `git submodule update --remote upstream` (moves pointer to latest).
   b. `git -C upstream diff <old>..<new> --stat` + name-status; classify changes against
      the Section-2 mapping checklist: new/removed skill dirs, new/removed template files,
      `settings.json` shape changes, new plugin marketplaces/plugins, new MCP servers,
      changed/added install steps.
   c. Apply matching edits to `modules/claude-code.nix` (add a skill to the file set, add a
      plugin/marketplace line to the activation script, update the settings.json builder…).
   d. Anything it cannot confidently classify → **do not guess**; note it in the PR body
      under "Needs review."
   e. `git checkout -b update-upstream-<shortsha>`, stage `upstream` pointer + module edits,
      commit, `gh pr create` with a summary of classified vs. needs-review changes.
- **Dry-run mode:** print the planned diff/edits without writing or opening a PR.

## Error handling

- Activation script guards on `command -v claude`; a missing binary logs a warning, does
  not fail the switch.
- rtk absent → hooks stripped, no failure (mirrors upstream).
- Skill: if `gh`/network/submodule fetch fails, it aborts with a clear message and makes
  no commits/PR. Unclassifiable upstream changes never auto-apply — they surface in the PR.

## Testing

- `nix flake check` (evaluation + module sanity) in CI/local.
- A home-manager `build` (dry activation) of an example config importing the module, to
  catch a bad upstream bump before it lands.
- Skill dry-run mode covers the "detect + plan" path without side effects.

## Prerequisites / setup steps (implementation)

1. `git init` (done), add submodule `upstream` → SkYNewZ/claude-code-bootstrap.
2. User creates the GitHub repo + remote (needed for the skill's PRs).
3. Consumer imports with `?submodules=1`.
