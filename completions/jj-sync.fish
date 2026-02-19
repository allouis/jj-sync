# jj-sync fish completion
# Place in ~/.config/fish/completions/jj-sync.fish

# Disable file completion by default
complete -c jj-sync -f

# Commands
complete -c jj-sync -n __fish_use_subcommand -a push -d 'Push WIP revisions and/or docs'
complete -c jj-sync -n __fish_use_subcommand -a pull -d 'Pull WIP revisions and/or docs'
complete -c jj-sync -n __fish_use_subcommand -a status -d 'Show sync status'
complete -c jj-sync -n __fish_use_subcommand -a gc -d 'Garbage collect old bookmarks'
complete -c jj-sync -n __fish_use_subcommand -a clean -d 'Remove all sync state'
complete -c jj-sync -n __fish_use_subcommand -a help -d 'Show help'

# Global options
complete -c jj-sync -l help -d 'Show help message'
complete -c jj-sync -l version -d 'Show version'
complete -c jj-sync -l dry-run -d 'Show what would be done'
complete -c jj-sync -l verbose -d 'Show verbose output'
complete -c jj-sync -l remote -d 'Specify sync remote (auto-detected if one remote)' -xa '(__fish_git_remotes)'
complete -c jj-sync -l user -d 'Specify user identity for ref namespacing'
complete -c jj-sync -l machine -d 'Specify machine name'

# Push/pull specific options
complete -c jj-sync -n '__fish_seen_subcommand_from push pull' -l docs -d 'Sync docs only'
complete -c jj-sync -n '__fish_seen_subcommand_from push pull' -l both -d 'Sync revisions and docs'

# GC/clean specific options
complete -c jj-sync -n '__fish_seen_subcommand_from gc clean' -l force -d 'Skip confirmation'

# Helper function for git remotes
function __fish_git_remotes
    if test -d .git; or test -d .jj
        git remote 2>/dev/null
    end
end
