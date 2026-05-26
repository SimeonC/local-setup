function grit_auto
  set diff_stat (git diff --stat)
  if test -n "$diff_stat"
    echo "You have uncommitted changes. Please commit or stash them before running grit_auto."
    echo "$diff_stat"
    return 1
  end
  for arg in $argv
    echo "Applying grit pattern $arg..."
    begin
      set pattern_file (find .grit/patterns -name "$arg.md" 2>/dev/null)
      if test -n "$pattern_file"
        set folder_path (grep -oE '^limit:\s*.*' $pattern_file | sed 's/^limit:\s*//' | string trim)
        if test -n "$folder_path"
          _pm_exec grit apply --force $arg $folder_path
        else
          _pm_exec grit apply --force $arg
        end
      else
        _pm_exec grit apply --force $arg
      end
      git add .
      echo "Checking for files to remove..."
      git diff --name-only --staged -z | xargs -0 grep -lz '^// DELETE grit delete file\s*$' | while read file
        git rm -f "$file"
      end; or true
      echo "Formatting files..."
      git add .
      set diff_files (git diff --name-only --staged --diff-filter=d)
      if test -n "$diff_files"
        _pm_exec eslint --fix $diff_files; or true
        _pm_exec prettier --write $diff_files; or true
      end
      echo "Committing changes..."
      git add .
      git commit -m "🚧 grit apply $arg" --no-verify
    end
    sleep 10
  end
  grit check --fix; or true
  git add .
  set diff_files (git diff --name-only --staged --diff-filter=d)
  if test -n "$diff_files"
    _pm_exec eslint --fix $diff_files; or true
    _pm_exec prettier --write $diff_files; or true
    git add .
    git commit -m "🚧 format all files" --no-verify
  end
  sleep 10
end
