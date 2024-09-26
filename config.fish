function aws_login
    set timestamp_file "/Users/simeon.cheeseman/.config/aws_codeartifact_last_login.txt"

    # Check if the timestamp file exists
    if not test -f $timestamp_file
        echo "0" > $timestamp_file
    end

    # Get the current timestamp
    set current_timestamp (date +%s)

    # Get the last execution timestamp from the file
    set last_execution_timestamp (cat $timestamp_file)

    # Calculate the elapsed time since the last execution
    set elapsed_time (math $current_timestamp - $last_execution_timestamp)

    # Check if the elapsed time is greater than or equal to 6 hours (21600 seconds)
    if test $elapsed_time -ge 21600
        echo "Logging into AWS CodeArtifact..."
        aws codeartifact login --tool npm --repository tablecheck --domain tablecheck --domain-owner 934763610305
        set_codeartifact_env
        # Update the timestamp file with the current timestamp
        echo $current_timestamp > $timestamp_file
    end
end

begin
  set -eg ASDF_DIR
  set -gx LC_ALL en_US.UTF-8
  set -gx LANG en_US.UTF-8
  set -gx PATH $PATH $HOME/bin
  set -gx PATH $PATH ./node_modules/.bin
  set -gx RAILS_ENV development
  set -gx TEST_ELASTICSEARCH true
  set -gx PATH /opt/homebrew/bin $PATH
  set -gx CPATH /opt/homebrew/include
  set -gx LIBRARY_PATH /opt/homebrew/lib
  set -g theme_title_display_process no
  set -g theme_title_display_path no
  set -g theme_title_display_user no
  set -g theme_title_use_abbreviated_path no
  set -g RECORD_REPLAY_API_KEY ruk_TbBGhacqeXZFrXMkEtBqslp2fnv57QmQo64lnEccm09
  set -gx EDITOR "code --wait"
  set -gx VISUAL "code --wait"
  set -gx VIEWER "code"
  set fish_greeting
  echo "GREETINGS"
  echo $PATH
  eval "$(pyenv init --path)"

  source /opt/homebrew/opt/asdf/libexec/asdf.fish
  asdf current

  npm config set save-exact=true
  alias strt start
  alias dv dev
  alias tst test_run
  alias tw test_watch
  alias bld build
  alias i install
  alias grt grit
  alias refactor "grit apply --force refactor"
  alias grt_clean grit_remove_debug
  alias audit "npm run audit"
  alias ql quality
  alias lint quality
  alias qf "quality --fix"
  alias format "quality --fix"
  alias m multi_run
  alias clog "npm run co:login"
  alias prw "prettier --log-level error -w ."
  alias "grit_refactor" "grit apply --force refactor; and prettier -w ."

end &> /dev/null

aws_login

# pnpm
set -gx PNPM_HOME "/Users/simeon.cheeseman/Library/pnpm"
set -gx PATH "$PNPM_HOME" $PATH
# pnpm end

launchctl setenv PATH $PATH