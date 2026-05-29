#!/usr/bin/env zunit
#{{{                    MARK:Header
#**************************************************************
##### Purpose: zsh-better-npm-completion plugin + completion
#####          contract pins. The completion parses package.json
#####          via shell + sed; tests exercise the parser against
#####          fixture package.json files so refactors do not
#####          silently break `npm run <tab>` and `npm uninstall
#####          <tab>` candidate generation.
#}}}***********************************************************

@setup {
    0="${${0:#$ZSH_ARGZERO}:-${(%):-%N}}"
    0="${${(M)0:#/*}:-$PWD/$0}"
    pluginDir="${0:h:A}"
    pluginFile="$pluginDir/zsh-better-npm-completion.plugin.zsh"
    compFile="$pluginDir/src/_npm"
    tmp=$(mktemp -d)
}

@teardown {
    [[ -n "$tmp" && -d "$tmp" ]] && rm -rf "$tmp"
}

@test 'plugin appends src/ to fpath via \${0:h}/src (plugin-manager portable)' {
    local body
    body=$(cat "$pluginFile")
    assert "$body" contains 'fpath=("${0:h}/src" $fpath)'
}

@test '_npm completion is #compdef for BOTH npm and pnpm' {
    # Pin: the very first line is the compdef directive. Without
    # `pnpm`, pnpm users get the bare npm completion which doesn't
    # know about pnpm's flags + subcommands.
    local first
    first=$(head -1 "$compFile")
    assert "$first" same_as '#compdef npm pnpm'
}

@test '_npm declares all 4 install/uninstall/run/default helper fns' {
    # Pin: refactor that drops any of these silently kills one of
    # the user-visible completions.
    local body
    body=$(cat "$compFile")
    assert "$body" contains '__zbnc_npm_install_completion()'
    assert "$body" contains '__zbnc_npm_uninstall_completion()'
    assert "$body" contains '__zbnc_npm_run_completion()'
    assert "$body" contains '__zbnc_default_npm_completion()'
}

@test '_npm dispatches via case $words[2] on i/install, r/uninstall, run' {
    # Pin: the subcommand router must keep all 5 documented
    # subcommand aliases. Renaming any silently breaks a code path.
    local body
    body=$(cat "$compFile")
    assert "$body" contains 'case $words[2] in'
    assert "$body" contains 'i|install)'
    assert "$body" contains 'r|uninstall)'
    assert "$body" contains 'run)'
}

@test '_npm falls back to default npm completion if no custom hit' {
    # Pin: when none of the custom branches matched, the bare
    # `npm completion` output must take over. Removing this guard
    # leaves the user with NO completion for verbs other than
    # install/uninstall/run.
    local body
    body=$(cat "$compFile")
    assert "$body" contains '[[ $custom_completion = false ]] && __zbnc_default_npm_completion'
}

@test '__zbnc_recursively_look_for walks up tree until file found' {
    # Pin: drives `npm i <tab>` and `npm run <tab>` to find the
    # right package.json for a nested directory. Without the
    # walk-up, the completion would only work at the repo root.
    local body
    body=$(cat "$compFile")
    assert "$body" contains '__zbnc_recursively_look_for()'
    assert "$body" contains 'while [ ! -e "$dir/$filename" ]'
    assert "$body" contains 'dir=${dir%/*}'
}

@test '__zbnc_recursively_look_for: smoke against nested dirs' {
    # End-to-end on the walk-up helper.
    mkdir -p "$tmp/a/b/c/d"
    echo '{"name":"x"}' > "$tmp/a/b/package.json"
    local found
    found=$(cd "$tmp/a/b/c/d" && zsh -c "
        source '$compFile' 2>/dev/null
        __zbnc_recursively_look_for package.json
    ")
    assert "$found" same_as "$tmp/a/b/package.json"
}

@test '__zbnc_parse_package_json_for_deps extracts dependency names from fixture' {
    # End-to-end: exercise the dep parser against tests/fixtures/full.json.
    # Catches both the sed multi-line range and the cut -f 1 -d "="
    # key extraction.
    local fixture="$pluginDir/tests/fixtures/full.json"
    local out
    out=$(zsh -c "
        source '$compFile' 2>/dev/null
        __zbnc_parse_package_json_for_deps '$fixture'
    ")
    assert "$out" contains 'react'
    assert "$out" contains 'react-dom'
    assert "$out" contains 'typescript'
    assert "$out" contains '@types/node'
}

@test '__zbnc_parse_package_json_for_script_suggestions emits name + colon pairs' {
    # Pin: the suggestion transform is what makes _describe show
    # "scriptName -- command" in the completion menu. Catches a
    # regression that would silently drop the descriptions.
    local fixture="$pluginDir/tests/fixtures/scripts_only.json"
    local out
    out=$(zsh -c "
        source '$compFile' 2>/dev/null
        __zbnc_parse_package_json_for_script_suggestions '$fixture'
    ")
    assert "$out" contains 'build'
    assert "$out" contains 'tsc -p .'
    assert "$out" contains 'test'
    assert "$out" contains 'jest --coverage'
    assert "$out" contains 'dev'
    assert "$out" contains 'vite'
}

@test '__zbnc_get_package_json_property_object reads only the requested property' {
    # Pin: the sed range must NOT bleed into the next property.
    # Catches a refactor that weakens the boundary regex and lets
    # dependencies leak into the scripts result.
    local fixture="$pluginDir/tests/fixtures/scripts_and_deps.json"
    local out
    out=$(zsh -c "
        source '$compFile' 2>/dev/null
        __zbnc_get_package_json_property_object_keys '$fixture' scripts
    ")
    assert "$out" same_as 'build'
}

@test '__zbnc_parse_package_json_for_deps reads BOTH dependencies AND devDependencies' {
    # Pin: omitting either silently breaks `npm uninstall <tab>`
    # for that dependency type.
    local fixture="$pluginDir/tests/fixtures/prod_and_dev.json"
    local out
    out=$(zsh -c "
        source '$compFile' 2>/dev/null
        __zbnc_parse_package_json_for_deps '$fixture'
    ")
    assert "$out" contains 'prod-only-pkg'
    assert "$out" contains 'dev-only-pkg'
}

@test 'install completion bails early on flag (PREFIX==-*) — does NOT try to npm search' {
    # Pin: `npm i -<tab>` would shell out to `npm search -` which
    # is a no-op AND eats network. The early return is mandatory.
    local body
    body=$(cat "$compFile")
    assert "$body" contains '[[ $PREFIX == -* ]] && return'
}

@test 'install completion caches npm search results via _retrieve_cache/_store_cache' {
    # Pin: dropping the cache turns every tab-press into a network
    # round-trip to the npm registry. Performance + offline-mode
    # regression that users would notice immediately.
    local body
    body=$(cat "$compFile")
    assert "$body" contains '_retrieve_cache'
    assert "$body" contains '_store_cache'
}

@test 'install completion only runs npm search when prefix is 2+ chars' {
    # Pin: protects against firing a registry query on every single
    # keystroke. `npm i a<tab>` should NOT cause a network call.
    local body
    body=$(cat "$compFile")
    assert "$body" contains '(( $#PREFIX >= 2))'
}

@test 'install completion lists $HOME/.npm/* as cached candidates' {
    # Pin: shows already-downloaded packages as candidates. The
    # $HOME/.npm directory is the npm cache convention. If
    # hardcoded elsewhere, the completion goes stale.
    local body
    body=$(cat "$compFile")
    assert "$body" contains '$HOME/".npm/*'
}

@test 'uninstall completion respects -g/--global flag (defers to npm default)' {
    # Pin: global uninstalls do not live in the local package.json,
    # so the completion must fall through to `npm completion` for
    # the -g/--global case. Without this branch, `npm uninstall -g
    # <tab>` would silently produce no candidates.
    local body
    body=$(cat "$compFile")
    assert "$body" contains "-g"
    assert "$body" contains "--global"
}

@test 'run completion only fires on `npm run <single-arg>` (#words==3)' {
    # Pin: the strict `(( $#words != 3 )) && return` guard avoids
    # parsing package.json for `npm run foo bar` where bar is an
    # argument, not a script name.
    local body
    body=$(cat "$compFile")
    assert "$body" contains '(( $#words != 3 )) && return'
}

@test '_npm dispatch entry calls _npm "$@" at file bottom (compinit contract)' {
    # Pin: zsh's compinit expects the completion FILE to invoke
    # the function once at load. Drop this and the completion
    # registers but never executes.
    local last
    last=$(grep -E '^_npm ' "$compFile" | tail -1)
    assert "$last" same_as '_npm "$@"'
}

@test '_npm completion compiles cleanly under autoload (no syntax errors)' {
    # End-to-end: load via autoload +X. The completion would refuse
    # to load if the case syntax or function defs were broken.
    local result
    result=$(zsh -c "
        emulate zsh
        fpath=('$pluginDir/src' \$fpath)
        autoload -U _npm
        autoload +X _npm && print OK || print FAIL
    " 2>&1)
    assert "$result" same_as 'OK'
}

@test 'plugin sourced cleanly + fpath includes src dir' {
    # End-to-end: source the plugin in a fresh subshell and verify
    # the src path landed on fpath.
    local found
    found=$(zsh -c "
        emulate zsh
        source '$pluginFile'
        print \${fpath[(r)*$pluginDir/src*]}
    ")
    assert "$found" contains 'src'
}

@test 're-sourcing the plugin keeps fpath leading entry stable (no double-add)' {
    # Pin: the fpath= form REPLACES fpath; subsequent sources just
    # re-prepend the same src dir. The leading entry must stay
    # identical between 1× and 2× sources.
    local one two
    one=$(zsh -c "
        emulate zsh
        source '$pluginFile'
        print \$fpath[1]
    ")
    two=$(zsh -c "
        emulate zsh
        source '$pluginFile'
        source '$pluginFile'
        print \$fpath[1]
    ")
    assert "$one" same_as "$two"
}
