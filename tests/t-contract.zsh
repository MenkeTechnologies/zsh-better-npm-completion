#!/usr/bin/env zunit
#{{{                    MARK:Header
##### Purpose: zsh-better-npm-completion — plugin-contract pins.
#####          Entrypoint stem matches plugin dir (typical
#####          zsh-plugin install pattern), entrypoint parses
#####          cleanly under `zsh -n`, and (where applicable)
#####          every completion file starts with `#compdef`.
#}}}***********************************************************

@setup {
    0="${${0:#$ZSH_ARGZERO}:-${(%):-%N}}"
    0="${${(M)0:#/*}:-$PWD/$0}"
    pluginDir="${0:h:A}"
}

@test 'entrypoint stem matches plugin directory basename' {
    # The standard zsh-plugin install pattern (oh-my-zsh, zinit,
    # antibody, antigen) sources `<repo>/<repo>.plugin.zsh`. The
    # stem of `zsh-better-npm-completion.plugin.zsh` must equal the parent directory's
    # basename so generated source lines stay copy-pasteable.
    local entry='zsh-better-npm-completion.plugin.zsh'
    local stem="${entry%.plugin.zsh}"
    local dir="${pluginDir##*/}"
    # Accept either exact match or `zsh-` prefix on dir (some repos
    # like `docker-aliases.plugin.zsh` live under `zsh-docker-aliases`).
    [[ "$stem" == "$dir" || "zsh-$stem" == "$dir" ]]
    assert $state equals 0
}

@test 'entrypoint parses cleanly under zsh -n' {
    run zsh -n "$pluginDir/zsh-better-npm-completion.plugin.zsh"
    assert $state equals 0
}

@test 'every completion file starts with #compdef directive' {
    # Pass trivially when there are no `_*` files; otherwise every
    # one must lead with `#compdef`. A missing directive silently
    # disables completion. Use `find` so a zero-match doesn't trip
    # nomatch under EXTENDED_GLOB.
    local missing=""
    local d f
    for d in "$pluginDir/completions" "$pluginDir"; do
        [[ -d "$d" ]] || continue
        while IFS= read -r f; do
            [[ -f "$f" ]] || continue
            run head -1 "$f"
            [[ "$output" =~ ^#compdef ]] || missing="$missing ${f##*/}"
        done < <(find "$d" -maxdepth 1 -name "_*" -type f 2>/dev/null)
    done
    assert "$missing" is_empty
}

#--------------------------------------------------------------
# Round 2: npm-completion routing pins
#--------------------------------------------------------------

@test 'src/_npm is the documented completion file' {
    # Pin: the completion lives at src/_npm; a future re-layout
    # (e.g. moving to completions/ or _npm at root) would silently
    # break fpath augmentation unless the directory + filename stay.
    [[ -f "$pluginDir/src/_npm" ]]
    assert $state equals 0
}

@test '_npm declares #compdef npm in its shebang line' {
    # Single `#compdef <cmd>` line registers the completion. The
    # file may bind multiple commands (`npm pnpm`); pin that `npm`
    # is among them.
    local first
    first=$(head -1 "$pluginDir/src/_npm")
    [[ "$first" == "#compdef "*npm* ]]
    assert $state equals 0
}

@test 'plugin augments fpath with src/ relative path (plugin-manager portable)' {
    local body
    body=$(cat "$pluginDir/zsh-better-npm-completion.plugin.zsh")
    assert "$body" contains 'fpath'
    assert "$body" contains 'src'
}

@test 'plugin self-locates via 0=\${${0:#}/...} pattern (zinit / antigen safe)' {
    # The plugin self-resolves its own path; pin presence so a
    # future minimal-deps refactor doesn't drop the resolution
    # logic and break plugin-manager installs.
    local body
    body=$(cat "$pluginDir/zsh-better-npm-completion.plugin.zsh")
    assert "$body" contains 'ZSH_ARGZERO'
}
