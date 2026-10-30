# Shared helpers, sourced (not executed) by the jj-* scripts in this dir.

# `jj bookmark advance`'s default target (bare @) can land on an empty,
# undescribed commit — e.g. right after `jj commit`, @ is the fresh empty
# child, not the work you just described. jj's own docs (`jj help -k
# config`, "### Set of immutable commits" section examples) show the fix:
# redefine `revsets.bookmark-advance-to` to the closest *pushable* ancestor
# (described, non-empty) instead of bare @. Passed inline via --config on
# every call so these tools work correctly regardless of the caller's own
# jj config — no dependency on this being set up globally first.
# shellcheck disable=SC2120
jj_advance_pushable() {
    jj \
        --config 'revsets.bookmark-advance-to=closest_pushable(@)' \
        --config 'revset-aliases."closest_pushable(to)"="heads(::to & mutable() & ~description(exact:\"\") & (~empty() | merges()))"' \
        bookmark advance "$@"
}

# jj has no `git push`/`git fetch` subprocess to pass `-c` to, but its git
# backend still resolves credential.helper from git config. This fleet's
# global ~/.gitconfig sets credential.helper=oauth (a device-flow helper,
# cached 1h) which hangs `jj git push`/`jj git fetch` on a browser flow
# once that cache expires. Call this before any jj command that talks to
# a remote — it overrides credential.helper for this process only, the
# same fix the fleet's own push-all/pull-all use via `git -c
# credential.helper=...`.
jj_use_gh_credential_helper() {
    export GIT_CONFIG_COUNT=2
    export GIT_CONFIG_KEY_0=credential.helper
    export GIT_CONFIG_VALUE_0=
    export GIT_CONFIG_KEY_1=credential.helper
    export GIT_CONFIG_VALUE_1='!gh auth git-credential'
}

# Reads subject lines on stdin; succeeds when one is the subject $1 itself
# or GitHub's squash form "$1 (#N)". A substring match would count a short
# subject ("fix") as merged whenever any trunk subject contains it. The
# concatenation with "" forces string comparison: awk compares number-like
# strings numerically ("1.0" == "1.00").
subject_merged() {
    S="$1" awk 'BEGIN { s = ENVIRON["S"] ""; n = length(s) }
        ($0 "") == s || (substr($0, 1, n + 3) == s " (#" && substr($0, n + 4) ~ /^[0-9]+\)$/) { f = 1; exit }
        END { exit !f }'
}

# The origin branch trunk() stands for, for GitHub's --base: the bookmark
# named by a simple `revset-aliases."trunk()"` ("name" or "name@origin"),
# else main, master or trunk on origin at the trunk() commit, as jj's
# built-in alias picks it. Prints nothing when that isn't certain, so a
# caller skips checks that need it rather than guessing another branch.
jj_trunk_branch() {
    local alias b
    alias=$(jj config get 'revset-aliases."trunk()"' 2>/dev/null | tr -d '[:space:]')
    if [[ "$alias" =~ ^([A-Za-z0-9._/-]+)(@origin)?$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    for b in main master trunk; do
        if [ -n "$(jj log -r "trunk() & remote_bookmarks(exact:\"$b\", exact:\"origin\")" --no-graph -T '"y"' 2>/dev/null)" ]; then
            echo "$b"
            return
        fi
    done
}
