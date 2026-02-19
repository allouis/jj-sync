# jj-sync bash completion
# Source this file or add to ~/.bash_completion.d/

_jj_sync() {
    local cur prev words cword
    _init_completion || return

    local commands="push pull status gc clean init help"
    local global_opts="--help --version --dry-run --verbose --remote --machine --force"
    local push_pull_opts="--docs --both"

    # Handle command completion
    if [[ $cword -eq 1 ]]; then
        COMPREPLY=($(compgen -W "$commands $global_opts" -- "$cur"))
        return
    fi

    local cmd="${words[1]}"

    case "$cmd" in
        push|pull)
            COMPREPLY=($(compgen -W "$push_pull_opts $global_opts" -- "$cur"))
            ;;
        gc|clean)
            COMPREPLY=($(compgen -W "--force $global_opts" -- "$cur"))
            ;;
        status|init|help)
            COMPREPLY=($(compgen -W "$global_opts" -- "$cur"))
            ;;
        --remote)
            # Complete with git remote names
            if [[ -d .git ]] || [[ -d .jj ]]; then
                local remotes
                remotes=$(git remote 2>/dev/null)
                COMPREPLY=($(compgen -W "$remotes" -- "$cur"))
            fi
            ;;
        *)
            COMPREPLY=($(compgen -W "$commands $global_opts" -- "$cur"))
            ;;
    esac

    # Handle --remote= style
    if [[ "$cur" == --remote=* ]]; then
        local prefix="${cur%%=*}="
        local remotes
        remotes=$(git remote 2>/dev/null)
        COMPREPLY=($(compgen -P "$prefix" -W "$remotes" -- "${cur#*=}"))
    fi
}

complete -F _jj_sync jj-sync
