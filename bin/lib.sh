# shellcheck shell=bash
# Shared helpers, sourced (not executed) by the jj-* scripts in this dir.

# A bare `jj bookmark advance` can land on the empty child that `jj commit`
# leaves as @. Advance to the closest pushable (described, non-empty or merge)
# ancestor instead, passed via --config so it works regardless of the caller's
# config.
# shellcheck disable=SC2120
jj_advance_pushable() {
    jj \
        --config 'revsets.bookmark-advance-to=closest_pushable(@)' \
        --config 'revset-aliases."closest_pushable(to)"="heads(::to & mutable() & ~description(exact:\"\") & (~empty() | merges()))"' \
        bookmark advance "$@"
}

# The global git config's credential.helper=oauth hangs `jj git push/fetch`
# on a browser login once its 1h cache expires. jj's git backend still reads
# credential.helper from git config, so override it to gh for this process.
# Call before any jj command that talks to a remote.
jj_use_gh_credential_helper() {
    export GIT_CONFIG_COUNT=2
    export GIT_CONFIG_KEY_0=credential.helper
    export GIT_CONFIG_VALUE_0=
    export GIT_CONFIG_KEY_1=credential.helper
    export GIT_CONFIG_VALUE_1='!gh auth git-credential'
}

# Reads subject lines on stdin; succeeds when one is $1 or GitHub's squash
# form "$1 (#N)". No substring match, so a short subject like "fix" doesn't
# count as merged. The `""` concat forces string comparison ("1.0" != "1.00").
subject_merged() {
    S="$1" awk 'BEGIN { s = ENVIRON["S"] ""; n = length(s) }
        ($0 "") == s || (substr($0, 1, n + 3) == s " (#" && substr($0, n + 4) ~ /^[0-9]+\)$/) { f = 1; exit }
        END { exit !f }'
}

# The origin branch trunk() stands for, for GitHub's --base: the bookmark in
# a simple `revset-aliases."trunk()"`, else main/master/trunk on origin at the
# trunk() commit. Prints nothing when unsure, so callers skip gh checks.
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

# Fails when an unpushed commit puts a closing keyword (fix, closes, resolved, ...)
# before an issue or PR of a repo that isn't one of our remotes (owner/repo#N or a URL):
# GitHub closes it once the commit lands on the default branch. JJ_ALLOW_EXTERNAL_CLOSE=1 skips.
jj_check_no_accidental_close() {
    [ "${JJ_ALLOW_EXTERNAL_CLOSE:-0}" = "1" ] && return 0

    local revset='mutable() & ~::remote_bookmarks() & ~description(exact:"")'
    local commits
    if ! commits=$(jj log -r "$revset" --no-graph -T 'change_id.shortest() ++ " " ++ description ++ "\n"'); then
        echo "⚠️  Could not list unpushed commits; skipping external-close check." >&2
        return 0
    fi
    [ -z "$commits" ] && return 0

    local pattern='(^|[[:space:]\("'\''`])(fix|fixes|fixed|close|closes|closed|resolve|resolves|resolved)(:|[[:space:]]+)[^[:space:]]*[[:space:]]*([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+|https://github\.com/[^/]+/[^/]+/(issues|pull)/[0-9]+)'
    local match
    match=$(printf '%s\n' "$commits" | grep -ioE "$pattern" || true)
    [ -z "$match" ] && return 0

    local remotes
    remotes=$(jj git remote list 2>/dev/null \
        | sed -nE 's#^[^[:space:]]+[[:space:]]+((https?|ssh)://)?([^/@[:space:]]+@)?github\.com[:/]+([^/[:space:]]+/[^/[:space:]]+)/?$#\4#p' \
        | sed 's/\.git$//' | tr '[:upper:]' '[:lower:]' || true)

    local line
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local target=""
        if [[ "$line" =~ ([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#[0-9]+ ]]; then
            target="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ https://github\.com/([^/]+/[^/]+)/(issues|pull)/[0-9]+ ]]; then
            target="${BASH_REMATCH[1]}"
        fi
        target=$(echo "$target" | tr '[:upper:]' '[:lower:]')

        if [ -n "$target" ] && ! echo "$remotes" | grep -qx "$target"; then
            echo "❌ Refusing to push: commit contains an issue-closing keyword before an external repository reference:" >&2
            echo "   $line" >&2
            echo "   GitHub will automatically close $target when this commit reaches the default branch!" >&2
            echo "   Change 'fix:'/'closes' to 'upstream:' (e.g. 'upstream: $target#...') before pushing." >&2
            echo "   (Set JJ_ALLOW_EXTERNAL_CLOSE=1 to bypass if intentional.)" >&2
            return 1
        fi
    done <<< "$match"

    return 0
}
