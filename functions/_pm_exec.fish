function _pm_exec
    # Translate npx-style invocations to the detected package manager.
    # Usage: _pm_exec <bin> [args...]
    # pnpm → pnpm exec <bin> <args>
    # bun  → bunx <bin> <args>
    # npm  → npx <bin> <args>
    set -l pm (_pm_detect)
    set -l bin $argv[1]
    set -l rest $argv[2..-1]
    switch $pm
        case pnpm
            pnpm exec $bin $rest
        case bun
            bunx $bin $rest
        case '*'
            npx $bin $rest
    end
end
