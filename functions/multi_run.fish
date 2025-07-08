function multi_run
  set source ''
  for cmd in $argv
    if test -n $source
      set source $source'; and '
    end
    set source $source''$cmd
  end
  set temp_file .multi_run.temp
  echo "rm $temp_file; and $source" > .multi_run.temp
  source $temp_file
end
