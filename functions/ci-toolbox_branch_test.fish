function ci-toolbox_branch_test
  set cmd "export TEST_BRANCH=\"$(git rev-parse --abbrev-ref HEAD)\" && source <(curl -fsSL -u \"tablecheck-private-automation:\$GITHUB_TOKEN\" https://raw.githubusercontent.com/tablecheck/ci-toolbox/\$TEST_BRANCH/install.sh)"
  printf "\e[90m> $cmd\e[0m\n"
  printf "\e[1;34m\e[1m\nCopied to clipboard. Run the command to install the ci-toolbox with the current branch.\n\n\e[0m"
  echo $cmd | pbcopy
end
