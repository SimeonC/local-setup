begin
  set -eg ASDF_DIR
  set -gx ASDF_CONFIG_FILE $HOME/.config/fish/configs/.asdfrc
  set -gx ASDF_NPM_DEFAULT_PACKAGES_FILE $HOME/.config/fish/configs/.default-npm-packages
  set -gx LC_ALL en_US.UTF-8
  set -gx LANG en_US.UTF-8
  set -gx PATH $HOME/.asdf/shims $PATH
  set -gx PATH $HOME/.grit/bin $PATH
  set -gx PATH $PATH $HOME/bin
  set -gx PATH $PATH ./node_modules/.bin
  set -gx RAILS_ENV development
  set -gx TEST_ELASTICSEARCH true
  set -gx PATH /opt/homebrew/bin $PATH
  set -gx CPATH /opt/homebrew/include
  set -gx LIBRARY_PATH /opt/homebrew/lib
  set -gx DENO_DIR "$HOME/Library/Caches/deno"
  set -g theme_title_display_process no
  set -g theme_title_display_path no
  set -g theme_title_display_user no
  set -g theme_title_use_abbreviated_path no
  set -gx EDITOR "cursor --wait"
  set -gx VISUAL "cursor --wait"
  set -gx VIEWER "cursor"
  set -U fish_complete_path $fish_complete_path ~/.config/fish/completions
  set fish_greeting

  source /opt/homebrew/opt/asdf/libexec/asdf.fish
  asdf current

  npm config set save-exact=true
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
  alias m multi_run
  alias clog "npm run co:login"
  alias prw smart_prettier
  alias "grit_refactor" "grit apply --force refactor; and prettier --log-level=error -w ."
  alias "grit_clean" "grit apply --force cleanup; and prettier --log-level=error -w ."

end &> /dev/null

aws_login

# pnpm
set -gx PNPM_HOME "$HOME/Library/pnpm"
set -gx PATH "$PNPM_HOME" $PATH
# pnpm end

launchctl setenv PATH "$PATH"
direnv hook fish | source
# Added by LM Studio CLI (lms)
set -gx PATH $PATH /Users/simeoncheeseman/.lmstudio/bin
