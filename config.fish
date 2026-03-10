set -gx MISE_NODE_DEFAULT_PACKAGES_FILE $HOME/.config/fish/configs/.default-npm-packages
set -gx LC_ALL en_US.UTF-8
set -gx LANG en_US.UTF-8
set -gx RAILS_ENV development
set -gx TEST_ELASTICSEARCH true
set -gx PNPM_HOME "$HOME/Library/pnpm"
set -gx DENO_DIR "$HOME/Library/Caches/deno"
set -gx EDITOR "cursor --wait"
set -gx VISUAL "cursor --wait"
set -gx VIEWER "cursor"

set -gx CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS "1"

# Theme settings
set -g theme_title_display_process no
set -g theme_title_display_path no
set -g theme_title_display_user no
set -g theme_title_use_abbreviated_path no
set fish_greeting

# Canonicalize PWD case after session restore (macOS case-insensitive FS)
if test (uname) = Darwin -a -d $PWD
    set -l canonical (stat -f "%N" $PWD 2>/dev/null)
    if test -n "$canonical"
        builtin cd $canonical
    end
end

# PATH (fast - direct instead of repeated appends)
fish_add_path --prepend $HOME/.grit/bin
fish_add_path --append /opt/homebrew/bin
fish_add_path --append ~/.local/bin
# fish_add_path automaticall resolves the path to the absolute path, we don't want that
set -gx PATH ./node_modules/.bin $PATH

set -gx CPATH /opt/homebrew/include
set -gx LIBRARY_PATH /opt/homebrew/lib

set -U fish_complete_path $fish_complete_path ~/.config/fish/completions

source ~/.config/fish/functions/secure/authorize_npm.fish
source ~/.config/fish/functions/secure/secure_env.fish

# Direnv (usually fast)
direnv hook fish | source

# Aliases
alias strt start
alias dv dev
alias tst test_run
alias tw test_watch
alias bld build
alias ni install
alias nci "install --clean"
alias ani "all_npm_projects_install"
alias audit "npm run audit"
alias ql quality
alias lint quality
alias qf "quality --fix"
alias format "quality --fix"
alias tc typecheck
alias m multi_run
alias clog "npm run co:login"
alias prw smart_prettier
alias grit_refactor "grit apply --force refactor; and prettier --log-level=error -w ."
alias grit_clean "grit apply --force cleanup; and prettier --log-level=error -w ."
alias record "replayio record"
alias dclaude danger_claude
alias ddclaude danger_danger_claude

function npm --wraps npm
    _npm_with_auth_refresh npm $argv
end
function npx --wraps npx
    _npm_with_auth_refresh npx $argv
end

# Manual activation for VSCode/Cursor terminal sessions compatibility
mise activate fish | source
# Added by LM Studio CLI (lms)
set -gx PATH $PATH /Users/simeoncheeseman/.lmstudio/bin
# End of LM Studio CLI section


# opencode
fish_add_path /Users/simeoncheeseman/.opencode/bin
