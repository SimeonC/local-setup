function danger_claude --description 'Start a devcontainer and run Claude Code with --dangerously-skip-permissions'
    argparse --ignore-unknown 'rebuild' -- $argv
    or return 1

    set -l dco_args
    if set -q _flag_rebuild
        set dco_args --rebuild
    end

    set -l claude_args --dangerously-skip-permissions $argv
    dco $dco_args "claude "(string join " " -- (string escape -- $claude_args))
end
