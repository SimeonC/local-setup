function cursor_rules_update
  echo "Syncing cursor rules from current directory to all projects"
  for dir in (ls -d ~/Development/*/)
    echo "Updating cursor rules for $dir"
    mkdir -p $dir.cursor/rules
    # Only copy files starting with MINE: prefix
    for rule in (ls .cursor/rules/*)
      set basename (basename $rule)
      if string match -q "MINE:*" $basename
        cp -v $rule $dir.cursor/rules/ 2>/dev/null
      end
    end
  end
end