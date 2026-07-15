function sclaude --description 'Orchestration mode claude planning'
    set -l instruction (string join ' ' -- $argv)
    claude "/plan /swarm
$instruction"
end
