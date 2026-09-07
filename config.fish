set -gx MISE_NODE_DEFAULT_PACKAGES_FILE $HOME/.config/fish/configs/.default-npm-packages
set -gx LC_ALL en_US.UTF-8
set -gx LANG en_US.UTF-8
set -gx RAILS_ENV development
set -gx TEST_ELASTICSEARCH true
set -gx PNPM_HOME "$HOME/Library/pnpm"
fish_add_path -g $PNPM_HOME/bin
set -gx DENO_DIR "$HOME/Library/Caches/deno"
set -gx EDITOR "zed --wait"
set -gx VISUAL "zed --wait"
set -gx VIEWER "zed"

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
fish_add_path --append /opt/homebrew/sbin
fish_add_path --append ~/.local/bin
# fish_add_path automaticall resolves the path to the absolute path, we don't want that
set -gx PATH ./node_modules/.bin $PATH

set -gx CPATH /opt/homebrew/include
set -gx LIBRARY_PATH /opt/homebrew/lib

if not contains ~/.config/fish/completions $fish_complete_path
    set -gx fish_complete_path $fish_complete_path ~/.config/fish/completions
end

source ~/.config/fish/functions/secure/authorize_npm.fish; or true
source ~/.config/fish/functions/secure/secure_env.fish; or true

# Direnv (usually fast)
direnv hook fish | source

# Aliases
alias fish_reload "source ~/.config/fish/config.fish"
alias strt start
alias dv dev
alias tst test_run
alias tw test_watch
alias bld build
alias ni install
alias nci "install --clean"
alias ani "all_npm_projects_install"
alias audit "_pm_run run audit"
alias ql quality
alias lint quality
alias qf "quality --fix"
alias format "quality --fix"
alias tc typecheck
alias m multi_run
alias clog "_pm_run run co:login"
alias prw smart_prettier
alias grit_refactor "grit apply --force refactor; and prettier --log-level=error -w ."
alias grit_clean "grit apply --force cleanup; and prettier --log-level=error -w ."
alias record "replayio record"
alias dclaude danger_claude
alias cclaude 'claude --continue'
alias qclaude quick_claude
alias kwatch 'open "kaleidoscope://changeset?path=$PWD"'
alias tower 'gittower .'

function npm --wraps npm
    _npm_with_auth_refresh npm $argv
end
function npx --wraps npx
    _npm_with_auth_refresh npx $argv
end
function pnpm --wraps pnpm
    _npm_with_auth_refresh pnpm $argv
end
function pnpx --wraps pnpx
    _npm_with_auth_refresh pnpx $argv
end
function aws --wraps aws
    if test (count $argv) -ge 2; and test "$argv[1]" = codeartifact; and test "$argv[2]" = login
        _npm_with_auth_refresh aws $argv
    else
        command aws $argv
    end
end

# Manual activation for VSCode/Cursor terminal sessions compatibility
mise activate fish | source
# Added by LM Studio CLI (lms)
set -gx PATH $PATH /Users/simeoncheeseman/.lmstudio/bin
# End of LM Studio CLI section


# opencode
fish_add_path /Users/simeoncheeseman/.opencode/bin

# pnpm
set -gx PNPM_HOME "/Users/simeoncheeseman/Library/pnpm"
if not string match -q -- "$PNPM_HOME/bin" $PATH
  set -gx PATH "$PNPM_HOME/bin" $PATH
end
# pnpm end

# AI helper aliases. The implementations are backend-neutral *_ai functions;
# set AI_BACKEND=pi (or claude) at the alias boundary.
alias pclaude 'set -lx AI_BACKEND claude; p_ai'
alias ppclaude 'set -lx AI_BACKEND claude; pp_ai'
alias prclaude 'set -lx AI_BACKEND claude; pr_ai'
alias semclaude 'set -lx AI_BACKEND claude; sem_ai'
alias quick_claude 'set -lx AI_BACKEND claude; quick_ai'
alias print_claude 'set -lx AI_BACKEND claude; print_ai'
alias danger_claude 'set -lx AI_BACKEND claude; danger_ai'

alias ppi 'set -lx AI_BACKEND pi; p_ai'
alias pclipboard 'set -lx AI_BACKEND pi; pp_ai'
alias pr_pi 'set -lx AI_BACKEND pi; pr_ai'
alias sem_pi 'set -lx AI_BACKEND pi; sem_ai'
alias quick_pi 'set -lx AI_BACKEND pi; quick_ai'
alias print_pi 'set -lx AI_BACKEND pi; print_ai'
alias danger_pi 'set -lx AI_BACKEND pi; danger_ai'
alias autoplan_pi 'set -lx AI_BACKEND pi; autoplan'
alias dco_pi 'dco pi'
