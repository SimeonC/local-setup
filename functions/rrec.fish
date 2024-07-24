function rrec
  set cache_file "$HOME/.config/fish/functions/.rrec_cache.cache"
  if not test -f $cache_file
    touch $cache_file
    echo 0 > $cache_file
  end
  set cache_time (cat $cache_file)
  set current_time (date +%s)
  set one_day 86400
  set elapsed_time (math "$current_time - $cache_time")

  if test $elapsed_time -gt $one_day
    set latest_version (npm show replayio@latest version)
    set installed_version (npm ls -g replayio | awk '/replayio/ {print $2}')
    if test "replayio@$latest_version" != "$installed_version"
      npm i -g replayio@latest
    end
    echo $current_time > $cache_file
  end
  replayio record $argv
end
