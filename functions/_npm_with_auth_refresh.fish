function _npm_with_auth_refresh
    set -l cmd $argv[1]
    set -l args $argv[2..]

    # Eager check: refresh if sidecar missing or token expires within 5 minutes
    set -l sidecar ~/.cache/codeartifact-token-expiry
    set -l needs_refresh 1
    if test -r $sidecar
        set -l exp (cat $sidecar 2>/dev/null)
        set -l now (date +%s)
        if string match -qr '^[0-9]+$' -- "$exp"
            if test (math "$exp - $now") -gt 300
                set needs_refresh 0
            end
        end
    end
    if test $needs_refresh -eq 1
        authorize_npm
    end

    # Run once, capturing stderr to a temp file while streaming it to terminal
    set -l tmpfile (mktemp)
    command $cmd $args 2>| tee $tmpfile >&2
    set -l status_code $pipestatus[1]

    if test $status_code -ne 0
        set -l err (cat $tmpfile)
        if string match -q -r -- "(401|unauthorized)" -- $err
            echo "🔑 Token expired, refreshing..."
            if authorize_npm
                echo "🔄 Retrying $cmd $args"
                command $cmd $args
                set status_code $status
            else
                echo "✗ Failed to refresh token"
            end
        end
    end

    rm -f $tmpfile
    return $status_code
end
