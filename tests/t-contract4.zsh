#!/usr/bin/env zunit
#{{{                    MARK:Header
##### Purpose: zsh-better-npm-completion — fourth-tier contracts.
#####          Pins for #compdef coverage (npm AND pnpm so workspace
#####          installs reach the same parser), dependency surfacing
#####          covers dependencies AND devDependencies (workspace/
#####          monorepo tooling needs both), and the recursive
#####          walk-up has no depth cap (walks until filesystem root).
#}}}***********************************************************

@setup {
    0="${${0:#$ZSH_ARGZERO}:-${(%):-%N}}"
    0="${${(M)0:#/*}:-$PWD/$0}"
    pluginDir="${0:h:A}"
    compFile="$pluginDir/src/_npm"
}

@test 'compdef directive covers BOTH npm and pnpm (workspace-aware tooling)' {
    # Pin: pnpm uses the same package.json scripts/deps shape, so the
    # parser must register for both. Removing pnpm regresses workspace
    # users whose primary CLI is pnpm.
    grep -qE '^#compdef[[:space:]]+npm[[:space:]]+pnpm' "$compFile"
    assert $? equals 0
}

@test 'uninstall completion surfaces BOTH dependencies AND devDependencies' {
    # Pin: __zbnc_parse_package_json_for_deps calls the keys helper
    # twice — once for `dependencies`, once for `devDependencies`. A
    # workspace project may declare a package as a devDependency in the
    # root and dependency in a child; both must be removable via tab.
    local count_deps count_devdeps
    count_deps=$(grep -cE '_object_keys .* dependencies$' "$compFile")
    count_devdeps=$(grep -cE '_object_keys .* devDependencies$' "$compFile")
    assert "$count_deps" same_as '1'
    assert "$count_devdeps" same_as '1'
}

@test '__zbnc_recursively_look_for has NO hardcoded depth cap (walks to /)' {
    # Pin: the while loop terminates only on `dir==""` (above /). A
    # depth-counter cap would silently fail to find package.json in
    # deeply-nested workspaces (pnpm monorepos often nest 4-6 levels).
    # Verify the loop body contains no integer counter increment.
    awk '/^__zbnc_recursively_look_for\(\)/,/^}/' "$compFile" > /tmp/zbnc_walk.$$
    ! grep -qE '\b(depth|counter|max_depth|i\+\+|i=i\+|i\=\$\(\(i)' /tmp/zbnc_walk.$$
    local r=$?
    rm -f /tmp/zbnc_walk.$$
    assert $r equals 0
}

@test 'walk-up termination uses dir=${dir%/*} (POSIX-only param expansion)' {
    # Pin: the parent-dir step strips one trailing path component via
    # `${dir%/*}`. Swapping to `dirname` would fork once per loop
    # iteration — N forks for an N-deep workspace. Pin the POSIX form.
    grep -qF 'dir=${dir%/*}' "$compFile"
    assert $? equals 0
}

@test 'install completion gates on PREFIX length >= 2 (no thrash on single char)' {
    # Pin: `npm i a<TAB>` would fire `npm search a` and return the
    # entire registry. The guard `(( $#PREFIX >= 2))` is what keeps
    # this from being a CPU/network catastrophe in monorepos with
    # many open shells. Pin the literal predicate.
    grep -qF '(( $#PREFIX >= 2))' "$compFile"
    assert $? equals 0
}
