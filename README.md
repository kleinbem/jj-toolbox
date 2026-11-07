# jj-toolbox

Single-repo jj helpers — each script runs against whatever jj+git repo
you're `cd`'d into, with no dependency on `kleinbem/repos.nix` or any
other fleet registry. These are the primitives that
[`kleinbem`](https://github.com/kleinbem/kleinbem)'s fan-out tooling
(`just jj::*`) delegates to per-repo, so the fan-out layer only does
orchestration and table rendering, not business logic.

Put `bin/` on `PATH` to use these directly.

| Script | What it does |
|---|---|
| `jj-save [--author "Name <email>"] <message>` | Describe the working-copy commit, advance the nearest bookmark to it, start a new one |
| `jj-push [args...]` | `jj git push`, with a credential-helper override (avoids hanging on an oauth device-flow helper) and one fetch+rebase+retry on a diverged remote |
| `jj-pull` | Fetch from origin, rebase onto `trunk()` (same credential-helper override as `jj-push`), then run `jj-abandon-merged` |
| `jj-abandon-merged [--dry-run] [--tsv]` | Abandon local copies of changes already on trunk — only when provable: every touched file identical on trunk, an identical patch on trunk (`git cherry`), or a local bookmark whose merged PR head is exactly that commit (bookmark forgotten too). Skips conflicts, any workspace's `@`, and anything unproven |
| `jj-sign-unsigned` | Re-sign every unsigned commit ahead of origin via `git rebase --exec ...--amend -S`. The one script here that rewrites history and drives a hardware signing key — advances trunk with `jj_advance_pushable` first, handles a detached git HEAD, and stashes/restores under a session-unique marker around the rebase |
| `jj-check-signatures` | Read-only signature audit of commits ahead of origin; exits 1 if any are unsigned |
| `jj-sweep-merged [--tsv]` | Read-only report of which local bookmarks are already merged and safe to forget |
| `jj-ws-new [name] [-r <revset>]` | Create an isolated jj workspace at `<repo>.ws/<name>/`, for a concurrent agent/session — on `trunk()`, or on an existing change with `-r` to move described work out of the primary checkout |
| `jj-ws-list [--tsv]` | List open workspaces for this repo plus each one's `@` state |
| `jj-ws-gc [--hours N] [--dry-run]` | Forget+delete workspaces older than N hours (default 4) that hold no work of their own: `@` empty and undescribed, every commit between trunk and `@` already merged (also squash-merged, or under a merged PR's head), no unsaved edits on disk. Handles stale workspaces too |

`--tsv` on the table-producing scripts prints raw tab-separated rows
instead of the pretty `column -t` output — for a caller that wants the
fields, not the formatting.
