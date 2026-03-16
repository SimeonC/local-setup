# Point SSH_AUTH_SOCK at 1Password's agent so all tools (git, ssh, Colima, etc.) use it
if test (uname) = Darwin
    set -l sock "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    if test -S "$sock"
        set -gx SSH_AUTH_SOCK "$sock"
        # Also set via launchctl so non-shell processes (e.g. Colima SSH agent forwarding) pick it up
        launchctl setenv SSH_AUTH_SOCK "$sock" 2>/dev/null
    end
end
