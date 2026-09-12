# jj-toolbox

This file provides guidance to Claude Code when working in this repository.

## What this is

Generic jj (Jujutsu) enhancements — each script in `bin/` runs against
whatever jj+git repo you're `cd`'d into, the same way `jj describe` does.
No dependency on `kleinbem/repos.nix` or any other fleet registry, no
assumption you're inside the kleinbem workspace at all. That's the whole
point of this repo existing separately from the fleet's other automation:
these are meant to work on *any* project.

`kleinbem`'s fan-out tooling (`kleinbem/tools/jj-fleet.sh`, driven by
`just jj::*`) calls INTO these scripts per-repo rather than duplicating
their logic — see "Cross-repo coupling" below before changing a script's
output format.

## Design principles — read before adding a tool

- **cwd-scoped, no fleet dependency.** No `$ROOT` walking, no repo-name
  argument, no reading `repos.nix`. A script takes at most a `name`/flags
  argument for itself, never "which repo" — that's what `cd` is for.
- **Don't hardcode `main`.** Detect the trunk bookmark instead:
  ```sh
  trunk=$(jj log -r 'trunk()' --no-graph -T 'local_bookmarks.map(|b| b.name()).join("\n")' 2>/dev/null | head -1)
  trunk="${trunk:-main}"
  ```
  (see `jj-sweep-merged`, `jj-check-signatures`, `jj-sign-unsigned` for the
  pattern in context). `trunk()` degrades to the root commit in a repo with
  no fetched remote, which is why the `main` fallback exists.
- **Portable, no exotic deps.** Plain `column -t`, not `gum`/`fzf` — this
  should work if someone puts `bin/` on `PATH` on a machine that's never
  heard of the kleinbem devshell. `git`, `jj`, `jq`, `gh` (optional, only
  where a script actually talks to GitHub) are the ceiling.
- **One script per file**, named `jj-<verb>`, executable, no file
  extension. Shared logic goes in `lib.sh` (sourced, never executed
  directly — no shebang, no +x).

## The `jj bookmark advance` gotcha — use `lib.sh`, not the bare command

`jj bookmark advance`'s default target is bare `@`. Right after `jj commit`
(describe + new), `@` is the *fresh empty child*, not the commit you just
described — advancing onto it drags the bookmark onto an empty commit, and
because jj auto-snapshot rewrites `@` in place, the bookmark then silently
absorbs whatever you type next, before you ever "save" it again. This is a
real bug we hit and fixed (see git history on `jj-save`/`jj-push`), not a
hypothetical.

Fix: `lib.sh`'s `jj_advance_pushable` passes jj's own documented
`closest_pushable(@)` revset override inline via `--config` on every call,
so it always lands on the closest *described, non-empty* ancestor —
correct whether you're right after `jj commit` (lands on the parent) or
mid-edit on a described-but-not-yet-`new`'d `@` (lands on `@` itself).

**Any new tool that moves a bookmark must `source lib.sh` and call
`jj_advance_pushable`, never a bare `jj bookmark advance`.**

## How the `jj <name>` aliases actually get wired up

Each script gets a matching alias via `jj util exec` — defined in
**`nix-presets/git.nix`** (`programs.jujutsu.settings.aliases`, built by
the `jjToolboxTool` helper there), **not in this repo**. That means:

1. Adding a new script here (`bin/jj-foo`) requires a matching
   `foo = jjToolboxTool "foo";` line in `nix-presets/git.nix` before
   `jj foo` exists as a command anywhere.
2. `nix-config`'s `flake.lock` pins a specific `nix-presets` commit —
   after pushing the `nix-presets` change, bump it:
   `cd nix-config && nix flake lock --update-input nix-presets`.
3. None of this is live until an actual `nixos-rebuild switch` runs
   (`just nixos::switch sudo` from `nix-config`, interactive — needs a
   real sudo password, can't be scripted headlessly). Skipping step 2
   is a real trap: nixos-nvme's nightly `nixos-upgrade.timer` rebuilds
   from the *committed* lockfile, so a manual switch using an
   uncommitted/unpinned override gets silently reverted on the next
   automatic upgrade.

### Testing an alias before any of that

`jj --config`/`--config-file` **cannot** load `[aliases]` — jj only reads
command aliases from a real, discovered config file path. Two ways to
test without waiting for a rebuild:

```sh
# Option A — invoke the script directly, skip the alias entirely:
/path/to/jj-toolbox/bin/jj-foo <args>

# Option B — actually exercise the alias, merge it into the real config
# (JJ_CONFIG replaces config discovery wholesale, so start from the real
# file or you'll lose signing/user settings):
cat ~/.config/jj/config.toml > /tmp/test.toml
cat >> /tmp/test.toml <<'EOF'
[aliases]
foo = ["util", "exec", "--", "/path/to/jj-toolbox/bin/jj-foo"]
EOF
JJ_CONFIG=/tmp/test.toml jj foo <args>
rm /tmp/test.toml
```

Always test in a scratch repo first (`mktemp -d && cd $_ && jj git init
--colocate`), especially for anything that touches bookmarks or history —
cheap to blow away, unlike a real checkout.

## Cross-repo coupling — `--tsv` output is a parsed interface

`jj-sweep-merged --tsv` and `jj-ws-list --tsv` print raw tab-separated
rows with a **fixed column order** that `kleinbem/tools/jj-fleet.sh`
parses directly (`while IFS=$'\t' read -r ...`) to re-decorate with a
REPO column for the fleet-wide dashboard. Changing a column's meaning,
order, or count in either script's `--tsv` mode breaks that fan-out
silently (no error, just misaligned/wrong fields) — check
`kleinbem/tools/jj-fleet.sh` for `--tsv` callers before changing one.

## Adding a new tool — checklist

1. `bin/jj-<verb>`, executable, cwd-scoped, sources `lib.sh` if it touches
   bookmarks.
2. Trunk detection instead of hardcoded `main`, if relevant.
3. `--tsv` mode (raw tab rows, no header, no formatting) if the tool
   produces a table AND a fleet-wide aggregator might want it — see
   "Cross-repo coupling" above before finalizing the column layout.
4. Test in a scratch repo.
5. Add the alias to `nix-presets/git.nix` (`jjToolboxTool "<verb>"`).
6. Update `README.md`'s table (user-facing: what it does) — this file is
   for conventions/gotchas, not a tool inventory.
7. If `kleinbem/tools/jj-fleet.sh` should fan this out too, wire it there
   the same way the existing tools are (per-repo loop calling this
   script, re-decorating with a REPO column) — see any of the existing
   `cmd_*` functions there for the pattern.

## Don't

- Don't add a fleet/`repos.nix` dependency — that's what `jj-fleet.sh` is
  for; this repo stays fleet-agnostic.
- Don't hardcode the trunk bookmark name.
- Don't call `jj bookmark advance` bare — use `jj_advance_pushable`.
- Don't add a `gum`/`fzf`/devshell-only dependency.
