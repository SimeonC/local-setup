function _pm_run
    # Translate npm-style invocations to the detected package manager.
    # Usage: _pm_run <cmd> [args...]
    #
    # Supported forms:
    #   i | install                → pm install
    #   ci                         → pm install --frozen-lockfile (or npm ci)
    #   i -D <pkg>                 → pm add -D/-d <pkg>
    #   i --ignore-scripts         → pm install --ignore-scripts
    #   i <pkg>                    → pm add <pkg>
    #   run <script> [-- <args>]   → pm <script> [<args>] (drops -- for pnpm/bun)
    #   start | test | stop        → pm <cmd> [args]
    #   -w <workspace> i <dep>     → pnpm --filter <workspace> add <dep>
    set -l pm (_pm_detect)
    set -l cmd $argv[1]
    set -l rest $argv[2..-1]

    switch $cmd
        case install i
            if test (count $rest) -eq 0
                switch $pm
                    case pnpm; pnpm install
                    case bun; bun install
                    case '*'; npm install
                end
            else if contains -- --ignore-scripts $rest
                switch $pm
                    case pnpm; pnpm install --ignore-scripts
                    case bun; bun install --ignore-scripts
                    case '*'; npm install --ignore-scripts
                end
            else if test "$rest[1]" = -D
                switch $pm
                    case pnpm; pnpm add -D $rest[2..-1]
                    case bun; bun add -d $rest[2..-1]
                    case '*'; npm install -D $rest[2..-1]
                end
            else
                switch $pm
                    case pnpm; pnpm add $rest
                    case bun; bun add $rest
                    case '*'; npm install $rest
                end
            end

        case ci
            switch $pm
                case pnpm; pnpm install --frozen-lockfile
                case bun; bun install --frozen-lockfile
                case '*'; npm ci
            end

        case run
            set -l script $rest[1]
            # Collect args after the -- separator
            set -l pass_args
            set -l after_sep 0
            for a in $rest[2..-1]
                if test "$a" = --
                    set after_sep 1
                else if test $after_sep -eq 1
                    set pass_args $pass_args $a
                end
            end
            switch $pm
                case pnpm
                    pnpm $script $pass_args
                case bun
                    bun run $script $pass_args
                case '*'
                    if test (count $pass_args) -gt 0
                        npm run $script -- $pass_args
                    else
                        npm run $script
                    end
            end

        case start test stop
            switch $pm
                case pnpm; pnpm $cmd $rest
                case bun; bun $cmd $rest
                case '*'
                    if test (count $rest) -gt 0
                        npm $cmd -- $rest
                    else
                        npm $cmd
                    end
            end

        case -w
            # Workspace install: _pm_run -w <workspace> i <dep>
            set -l workspace_pkg $rest[1]
            set -l dep $rest[3..-1]
            switch $pm
                case pnpm
                    pnpm --filter $workspace_pkg add $dep
                case bun
                    # bun workspace add not supported; fall back to npm
                    npm install -w $workspace_pkg $dep
                case '*'
                    npm install -w $workspace_pkg $dep
            end

        case '*'
            switch $pm
                case pnpm; pnpm $cmd $rest
                case bun; bun $cmd $rest
                case '*'; npm $cmd $rest
            end
    end
end
