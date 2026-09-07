function pi --wraps pi --description "pi, with Anthropic-direct credentials stripped so only Pantheon-sourced models appear"
    open "kaleidoscope://changeset?path=$PWD"
    # Use `AI_BACKEND=pi claude ...` or one of the *_pi helpers for shared flows.
    # secure_env.fish exports ANTHROPIC_AUTH_TOKEN/ANTHROPIC_BASE_URL for Claude Code.
    # pi treats those as auth for its built-in `anthropic` provider, which makes all 13
    # api.anthropic.com models show up in /model alongside the Pantheon ones.
    # Stripping them here leaves only the `pantheon` and `pantheon-code` providers
    # defined in ~/.pi/agent/models.json, which authenticate via $PANTHEON_API_KEY.
    env -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_API_KEY -u ANTHROPIC_BASE_URL command pi $argv
end
