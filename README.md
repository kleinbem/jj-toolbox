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
| `jj-pull` | Fetch from origin and rebase onto `trunk()`, same credential-helper override as `jj-push` |
| `jj-sign-unsigned` | Re-sign every unsigned commit ahead of origin via `git rebase --exec ...--amend -S`. The one script here that rewrites history and drives a hardware signing key — advances trunk with `jj_advance_pushable` first, handles a detached git HEAD, and stashes/restores under a session-unique marker around the rebase |
| `jj-check-signatures` | Read-only signature audit of commits ahead of origin; exits 1 if any are unsigned |
| `jj-sweep-merged [--tsv]` | Read-only report of which local bookmarks are already merged and safe to forget |
| `jj-ws-new [name]` | Create an isolated jj workspace at `<repo>.ws/<name>/`, for a concurrent agent/session |
| `jj-ws-list [--tsv]` | List open workspaces for this repo plus each one's `@` state |
| `jj-ws-gc [--hours N]` | Forget+delete workspaces that are empty, undescribed, and older than N hours (default 4) |

`--tsv` on the table-producing scripts prints raw tab-separated rows
instead of the pretty `column -t` output — for a caller that wants the
fields, not the formatting.
