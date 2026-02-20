# refsync fish completion
# Place in ~/.config/fish/completions/refsync.fish

# Disable file completion by default
complete -c refsync -f

# Commands
complete -c refsync -n __fish_use_subcommand -a push -d 'Push WIP revisions and/or docs'
complete -c refsync -n __fish_use_subcommand -a pull -d 'Pull WIP revisions and/or docs'
complete -c refsync -n __fish_use_subcommand -a status -d 'Show sync status'
complete -c refsync -n __fish_use_subcommand -a gc -d 'Garbage collect old bookmarks'
complete -c refsync -n __fish_use_subcommand -a clean -d 'Remove all sync state'
complete -c refsync -n __fish_use_subcommand -a help -d 'Show help'

# Global options
complete -c refsync -l help -d 'Show help message'
complete -c refsync -l version -d 'Show version'
complete -c refsync -l dry-run -d 'Show what would be done'
complete -c refsync -l verbose -d 'Show verbose output'
complete -c refsync -l remote -d 'Specify sync remote (auto-detected if one remote)' -xa '(__fish_git_remotes)'
complete -c refsync -l user -d 'Specify user identity for ref namespacing'
complete -c refsync -l machine -d 'Specify machine name'

# Push/pull specific options
complete -c refsync -n '__fish_seen_subcommand_from push pull' -l docs -d 'Sync docs only (dirs override REFSYNC_DOCS)'
complete -c refsync -n '__fish_seen_subcommand_from push pull' -l revs -d 'Sync revisions only (requires jj)'
complete -c refsync -n '__fish_seen_subcommand_from push pull' -l both -d 'Sync revisions + docs (dirs override REFSYNC_DOCS)'

# GC/clean specific options
complete -c refsync -n '__fish_seen_subcommand_from gc clean' -l force -d 'Skip confirmation'

# Helper function for git remotes
function __fish_git_remotes
    if test -d .git; or test -d .jj
        git remote 2>/dev/null
    end
end
