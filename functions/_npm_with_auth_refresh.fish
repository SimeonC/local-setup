function _npm_with_auth_refresh
    set -l cmd $argv[1]
    set -l args $argv[2..]

    command $cmd $args
    set -l status_code $status

    if test $status_code -ne 0
        set -l error_output (command $cmd $args 2>&1 | tail -n 20)
        if string match -q -r "(401|unauthorized)" $error_output
            echo "🔑 Token expired, refreshing..."
            if authorize_npm
                echo "🔄 Retrying $cmd $args"
                command $cmd $args
                return $status
            else
                echo "✗ Failed to refresh token"
            end
        end
    end

    return $status_code
end