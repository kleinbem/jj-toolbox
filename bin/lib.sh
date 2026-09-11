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
