function smart_prettier
  set modified_files (git diff --name-only --diff-filter=ACMTRUX HEAD 2>/dev/null)
  if test $status -ne 0
    set modified_files
  end
  echo "Prettier Version: " (npx prettier --version)
  if test "$argv" = "--force"; or test "$argv" = "-f"
    echo (set_color yellow)"Force formatting all files"(set_color normal)
    npx prettier --log-level error --write .
  else if test (count $modified_files) -eq 0
    echo (set_color green)"No changes or not a git repository, formatting all files"(set_color normal)
    npx prettier --log-level error --write .
  else
    echo (set_color yellow)"Formatting "(count $modified_files)" changed files"(set_color normal)
    npx prettier --log-level error --write $modified_files
  end
end
