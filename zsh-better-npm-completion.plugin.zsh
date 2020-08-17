
__zbnc_npm_command_arg() {
    echo "${words[3]}"
}

__zbnc_list_cached_modules() {
    ls ~/.npm 2>/dev/null
}

__zbnc_recursively_look_for() {
    local filename="$1"
    local dir=$PWD
    while [ ! -e "$dir/$filename" ]; do
        dir=${dir%/*}
        [[ "$dir" = "" ]] && break
    done
    [[ ! "$dir" = "" ]] && echo "$dir/$filename"
}

__zbnc_get_package_json_property_object() {
    local package_json="$1"
    local property="$2"
    cat "$package_json" |
        sed -nE "/^  \"$property\": \{$/,/^  \},?$/p" | # Grab scripts object
        sed '1d;$d' |                                   # Remove first/last searchLines
        sed -E 's/    "([^"]+)": "(.+)",?/\1=>\2/'      # Parse into key=>value
    }

__zbnc_get_package_json_property_object_keys() {
    local package_json="$1"
    local property="$2"
    __zbnc_get_package_json_property_object "$package_json" "$property" | cut -f 1 -d "="
}

__zbnc_parse_package_json_for_script_suggestions() {
    local package_json="$1"
    __zbnc_get_package_json_property_object "$package_json" scripts |
        sed -E 's@(.+)=>(.+)@\1:$ \2@' |  # Parse commands into suggestions
        sed 's@\(:\)[^$]@\\&@g' |         # Escape ":" in commands
        sed 's@\(:\)$[^ ]@\\&@g'          # Escape ":$" without a space in commands
    }

__zbnc_parse_package_json_for_deps() {
    local package_json="$1"
    __zbnc_get_package_json_property_object_keys "$package_json" dependencies
    __zbnc_get_package_json_property_object_keys "$package_json" devDependencies
}

__zbnc_npm_install_completion() {

    local -a searchLines
    local -a cachedLines
    local -a npmSearchPackages
    local package desc lastWord out
    lastWord=${${words[-1]}// /}

    #npm i -<tab>
    [[ $lastWord == -* ]] && return

    #npm i ab<tab>
    if (( $#words >= 3 )) && [[ $lastWord != '' ]] && (( $#lastWord >= 2)); then
        searchLines=("${(f@)$(npm search $words[-1])}")

        for needle in $searchLines[@]; do
            if [[ $needle == (#b)([^[:space:]]##)[[:space:]]##(*) ]]; then
                npmSearchPackages+=("$match[1]:$match[2]")
            else
                echo "ERROR: npm search output: $needle is not in expected format." >&2
            fi
        done

        _describe -t npm-search 'npm search packages' npmSearchPackages
        # Make sure we don't run default completion
        custom_completion=true
    fi


    out="$(__zbnc_list_cached_modules)"
    if [[ $out != "" ]];then
        cachedLines=("${(ufA@)out}")
        _wanted npm-cache expl 'cached npm packages' compadd -Q $cachedLines
        # Make sure we don't run default completion
        custom_completion=true
    fi
    set +x

}

__zbnc_npm_uninstall_completion() {

  # Use default npm completion to recommend global modules
  [[ "$(__zbnc_npm_command_arg)" = "-g" ]] ||  [[ "$(__zbnc_npm_command_arg)" = "--global" ]] && return

  # Look for a package.json file
  local package_json="$(__zbnc_recursively_look_for package.json)"

  # Return if we can't find package.json
  [[ "$package_json" = "" ]] && return

  _values $(__zbnc_parse_package_json_for_deps "$package_json")

  # Make sure we don't run default completion
  custom_completion=true
}

__zbnc_npm_run_completion() {

  # Only run on `npm run ?`
  (( $#words != 3 )) && return

  # Look for a package.json file
  local package_json="$(__zbnc_recursively_look_for package.json)"

  # Return if we can't find package.json
  [[ "$package_json" = "" ]] && return

  # Parse scripts in package.json
  local -a options
  options=(${(f)"$(__zbnc_parse_package_json_for_script_suggestions $package_json)"})

  # Return if we can't parse it
  [[ "$#options" = 0 ]] && return

  # Load the completions
  _describe 'values' options

  # Make sure we don't run default completion
  custom_completion=true
}

__zbnc_default_npm_completion() {
    compadd -- $(COMP_CWORD=$((CURRENT-1)) \
        COMP_LINE=$BUFFER \
        COMP_POINT=0 \
        npm completion -- "${words[@]}" \
        2>/dev/null)
    }

_zbnc_zsh_better_npm_completion() {

  # Store custom completion status
  local custom_completion=false

  # Load custom completion commands
  case $words[2] in
      i|install)
          __zbnc_npm_install_completion
          ;;
      r|uninstall)
          __zbnc_npm_uninstall_completion
          ;;
      run)
          __zbnc_npm_run_completion
          ;;
  esac

  # Fall back to default completion if we haven't done a custom one
  [[ $custom_completion = false ]] && __zbnc_default_npm_completion
}

compdef _zbnc_zsh_better_npm_completion npm
