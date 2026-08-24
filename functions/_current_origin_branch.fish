function _current_origin_branch
    # The branch we're effectively working on, resolved against origin. A local
    # branch tracking an origin branch IS that origin branch — e.g. local
    # `theme/details-styling-refactor` tracking `origin/details-styling-refactor`
    # reports as `details-styling-refactor`. Detached HEAD (no current branch)
    # returns empty; callers fall back to their PR/detached handling.
    set -l local (git branch --show-current 2>/dev/null)
    if test -z "$local"
        return 0
    end
    set -l upstream (git rev-parse --abbrev-ref "$local@{upstream}" 2>/dev/null)
    if test -n "$upstream"; and string match -q 'origin/*' -- $upstream
        string replace -r '^origin/' '' -- $upstream
    else
        echo $local
    end
end
