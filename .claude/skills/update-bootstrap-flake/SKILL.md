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
| `rtk` released a new version (check `cargo`/crates.io; not in the submodule) | Bump `version` + `src.hash` + `cargoHash` in `pkgs/rtk.nix` (use `lib.fakeHash` then read the correct hash from the build error). |

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
