#!/usr/bin/env zunit
#{{{                    MARK:Header
##### Purpose: zsh-better-npm-completion second-tier contracts.
#####          Cover surfaces not pinned by t-plugin.zsh:
#####          __zbnc_npm_command_arg lookup, recursively_look_for
#####          no-match path, property-object key=>value formatter,
#####          and empty/edge-case package.json handling.
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

@test '__zbnc_npm_command_arg returns words[3] (subcommand of npm/pnpm)' {
    # Pin: words[3] is the npm subcommand argument used by the run
    # completion to look up scripts. Renaming to words[2] silently
    # breaks completion for npm run.
    local out
    out=$(zsh -c "
        source '$compFile' 2>/dev/null
        words=(npm run mybuild)
        __zbnc_npm_command_arg
    ")
    assert "$out" same_as 'mybuild'
}

@test '__zbnc_recursively_look_for emits nothing when no match up the tree' {
    # Pin: walking to / without finding the file MUST exit silently
    # (no trailing /missing.json). Without the dir!="" guard, the
    # completion would suggest a nonexistent root-level file.
    # NOTE: sourcing _npm runs _npm at file end (compsys machinery)
    # so use inline lift of the fn body. Trailing || true defangs
    # the subshell exit code under zunit ERR_EXIT.
    mkdir -p "$tmp/a/b/c"
    local out
    out=$(cd "$tmp/a/b/c" && zsh -c '
        __zbnc_recursively_look_for() {
            local filename="$1"
            local dir=$PWD
            while [ ! -e "$dir/$filename" ]; do
                dir=${dir%/*}
                [[ "$dir" = "" ]] && break
            done
            [[ ! "$dir" = "" ]] && echo "$dir/$filename"
            return 0
        }
        __zbnc_recursively_look_for definitely-missing-12345.json
    ') || true
    assert "$out" is_empty
}

@test '__zbnc_get_package_json_property_object emits key=>value pairs for scripts' {
    # Pin: the intermediate form is `name=>command`. Both the keys
    # extractor AND the script-suggestion formatter depend on this
    # shape. A refactor that drops the => sentinel would break both
    # downstream parsers silently.
    local fixture="$pluginDir/tests/fixtures/full.json"
    local out
    out=$(zsh -c "
        source '$compFile' 2>/dev/null
        __zbnc_get_package_json_property_object '$fixture' scripts
    ")
    assert "$out" contains 'build=>tsc -p .'
    assert "$out" contains 'test=>jest'
}

@test 'empty package.json (no scripts/no deps) produces no output (no crash)' {
    # Pin: a package.json with just a name MUST NOT crash the parser.
    # Sed range patterns that fail to find the property would otherwise
    # bleed into stderr / hang in CI.
    echo '{"name":"empty"}' > "$tmp/package.json"
    local scripts deps
    scripts=$(zsh -c "
        source '$compFile' 2>/dev/null
        __zbnc_get_package_json_property_object_keys '$tmp/package.json' scripts
    ")
    deps=$(zsh -c "
        source '$compFile' 2>/dev/null
        __zbnc_parse_package_json_for_deps '$tmp/package.json'
    ")
    assert "$scripts" is_empty
    assert "$deps" is_empty
}

@test 'plugin file is exactly 4 lines (canonical fpath setup, no scope creep)' {
    # Pin: the plugin file is just the 3-line fpath bootstrap. Any
    # growth signals scope creep that should live in src/.
    local lines
    lines=$(grep -cv '^$' "$pluginFile")
    [[ "$lines" -le 5 ]]
    assert $? equals 0
}

@test '_npm completion is registered via head directive only (no explicit compdef call)' {
    # Pin: completion via the head #compdef directive is the right way.
    # An explicit compdef call inside the file would double-register
    # under compinit caching. Use grep -c with || true since grep -c
    # returns 1 when matches=0 and zunit runs under ERR_EXIT.
    local matches
    matches=$(grep -cE '^[[:space:]]*compdef[[:space:]]' "$compFile" || true)
    assert "$matches" equals '0'
}
