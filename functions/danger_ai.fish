function danger_ai --description 'Start a devcontainer and run Claude Code with --dangerously-skip-permissions'
    argparse --ignore-unknown 'rebuild' -- $argv
    or return 1

    set -l dco_args
    if set -q _flag_rebuild
        set dco_args --rebuild
    end

    set -l claude_args $argv
    set -l agent_command claude
    if test "$AI_BACKEND" = pi
        set agent_command pi
    else
        set claude_args --dangerously-skip-permissions $argv
    end
    dco $dco_args "$agent_command "(string join " " -- (string escape -- $claude_args))
end
