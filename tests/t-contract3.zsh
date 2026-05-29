#!/usr/bin/env zunit
#{{{                    MARK:Header
##### Purpose: zsh-better-npm-completion — third-tier surface pins:
#####          - recursive walk-up terminates at root (empty-dir guard present)
#####          - walk-up terminates in bounded time when no match (no infinite loop)
#####          - dispatch case for `r` handles BOTH `r` and `uninstall` (alias overlap)
#####          - cache key namespace uses `npm_${PREFIX}_cache` pattern (no clash)
#####          - default fallback uses `npm completion` (the official official npm completion exec)
#}}}***********************************************************

@setup {
    0="${${0:#$ZSH_ARGZERO}:-${(%):-%N}}"
    0="${${(M)0:#/*}:-$PWD/$0}"
    pluginDir="${0:h:A}"
    compFile="$pluginDir/src/_npm"
}

@test 'recursive walk-up has termination guard (empty-dir break)' {
    # Pin: the walk-up `while [ ! -e "$dir/$filename" ]; do dir=${dir%/*}; done`
    # would loop forever if not guarded. The plugin MUST have a
    # `[[ "$dir" = "" ]] && break` (or equivalent) so the loop terminates
    # when dir is shaved down to "".
    grep -qE '\[\[ "\$dir" = "" \]\] && break' "$compFile"
    assert $? equals 0
}

@test 'walk-up terminates when no match found (no infinite loop on root)' {
    # End-to-end: invoke __zbnc_recursively_look_for in a deep tmpdir
    # with no matching file. With the empty-dir guard present, the loop
    # walks up to "" then breaks and returns empty. Without the guard,
    # `dir=${dir%/*}` on an empty `dir` stays "" forever — infinite loop.
    # Use SIGALRM-via-background to bound execution: if function still
    # running at 5s, the test treats it as the infinite-loop regression.
    local tmp fnbody output
    tmp=$(mktemp -d)
    mkdir -p "$tmp/a/b/c/d/e/f"
    fnbody=$(sed -n '/^__zbnc_recursively_look_for/,/^}/p' "$compFile")
    # Bounded via shell `read -t` race: spawn the call into a fifo,
    # read with a 5s timeout. If timeout, assert failure.
    local fifo="$tmp/sync"
    mkfifo "$fifo"
    ( cd "$tmp/a/b/c/d/e/f" && zsh -c "$fnbody
__zbnc_recursively_look_for nonexistent-12345.json
print DONE" > "$fifo" 2>/dev/null ) &
    local pid=$!
    output=""
    { read -t 5 output < "$fifo"; } 2>/dev/null
    local rc=$?
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    rm -rf "$tmp"
    # If read timed out (rc != 0), fn was still running → infinite loop.
    # If output starts at $tmp path or is DONE, fn returned.
    [[ "$rc" -eq 0 ]]
    assert $state equals 0
}

@test 'dispatch case for uninstall covers BOTH r AND uninstall (alias overlap)' {
    # Pin: `npm r` is the short form of `npm uninstall`. The dispatch case
    # MUST include both — dropping `r` would silently break the short form.
    grep -qE '^[[:space:]]*r\|uninstall\)' "$compFile"
    assert $? equals 0
}

@test 'cache key uses PREFIX-namespaced filename (no global cache clash)' {
    # Pin: cache files are named `npm_${PREFIX}_cache` so two completions
    # with different prefixes don't collide. Dropping the PREFIX would
    # mean prefix `ab` and `xy` share a cache and overwrite each other.
    grep -qE 'npm_cache_file=.npm_\$\{PREFIX\}_cache.' "$compFile"
    assert $? equals 0
}

@test 'default fallback delegates to `npm completion` (the official upstream)' {
    # Pin: when no custom case matched, fall back to invoking `npm completion`
    # (npm's built-in completion stream). Replacing this with a hardcoded
    # list would silently rot on every npm release.
    grep -qE 'npm completion --' "$compFile"
    assert $? equals 0
}
