function _pm_detect
    # Detect package manager from lockfile. Accepts optional dir arg, defaults to $PWD.
    # Walks up from dir to find nearest package.json, then checks lockfiles there.
    if test (count $argv) -gt 0
        set -l search_dir $argv[1]
    else
        set -l search_dir $PWD
    end
    while test -n "$search_dir"; and test "$search_dir" != /
        if test -f "$search_dir/package.json"
            if test -f "$search_dir/pnpm-lock.yaml"
                echo pnpm
            else if test -f "$search_dir/bun.lockb"; or test -f "$search_dir/bun.lock"
                echo bun
            else
                echo npm
            end
            return
        end
        set search_dir (dirname $search_dir)
    end
    echo npm
end
