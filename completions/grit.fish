# Autocomplete for grit_auto command
function __fish_grit_complete
  for file in (find ./.grit/patterns -type f)
    set filename (basename $file)
    set pattern (string split -r . $filename)[1]
    echo $pattern
  end
end

set -l commands check list apply doctor blueprints auth install init workflows patterns version help
complete -c grit -f

complete -c timedatectl -n "not __fish_seen_subcommand_from $commands" \
    -a "list patterns doctor blueprints auth install init workflows version help"

complete -c grit -n "__fish_seen_subcommand_from apply" -a "(__fish_grit_complete)"

complete -c grit -n "__fish_seen_subcommand_from apply" -l force -d "Ignore any git changes and apply the pattern anyway"
complete -c grit -n "__fish_seen_subcommand_from check" -l fix -d "Fix any autofixable checks"

set -l pattern_subcommands list test edit describe
complete -c grit -n "__fish_seen_subcommand_from patterns" -n "not __fish_seen_subcommand_from $pattern_subcommands" -a "list" -d "List all available named patterns"
complete -c grit -n "__fish_seen_subcommand_from patterns" -n "not __fish_seen_subcommand_from $pattern_subcommands" -a "test" -d "Test patterns against expected output"
complete -c grit -n "__fish_seen_subcommand_from patterns" -n "not __fish_seen_subcommand_from $pattern_subcommands" -a "edit" -d "Open a pattern in the studio"
complete -c grit -n "__fish_seen_subcommand_from patterns" -n "not __fish_seen_subcommand_from $pattern_subcommands" -a "describe" -d "Describe a pattern"

complete -c grit -n "not __fish_seen_subcommand_from $commands" -a "check" -d "Check the current directory for pattern violations"
complete -c grit -n "not __fish_seen_subcommand_from $commands" -a "list" -d "List everything that can be applied to the current directory"
complete -c grit -n "not __fish_seen_subcommand_from $commands" -a "apply" -d "Apply a pattern or migration to a set of files"
complete -c grit -n "not __fish_seen_subcommand_from $commands" -a "doctor" -d "Print diagnostic information about the current environment"
complete -c grit -n "not __fish_seen_subcommand_from $commands" -a "blueprints" -d "Manage blueprints for the Grit Agent"
complete -c grit -n "not __fish_seen_subcommand_from $commands" -a "auth" -d "Authentication commands, run `grit auth --help` for more information"
complete -c grit -n "not __fish_seen_subcommand_from $commands" -a "install" -d "Install supporting binaries"
complete -c grit -n "not __fish_seen_subcommand_from $commands" -a "init" -d "Install grit modules"
complete -c grit -n "not __fish_seen_subcommand_from $commands" -a "workflows" -d "Workflow commands, run `grit workflows --help` for more information"
complete -c grit -n "not __fish_seen_subcommand_from $commands" -a "patterns" -d "Patterns commands, run `grit patterns --help` for more information"
complete -c grit -n "not __fish_seen_subcommand_from $commands" -a "version" -d "Display version information about the CLI and agents"
complete -c grit -s h -l "help" -d "Print this message or the help of the given subcommand(s)"
