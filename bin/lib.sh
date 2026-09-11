# Shared helpers, sourced (not executed) by the jj-* scripts in this dir.

# `jj bookmark advance`'s default target (bare @) can land on an empty,
# undescribed commit — e.g. right after `jj commit`, @ is the fresh empty
# child, not the work you just described. jj's own docs (`jj help -k
# config`, "### Set of immutable commits" section examples) show the fix:
# redefine `revsets.bookmark-advance-to` to the closest *pushable* ancestor
# (described, non-empty) instead of bare @. Passed inline via --config on
# every call so these tools work correctly regardless of the caller's own
# jj config — no dependency on this being set up globally first.
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
