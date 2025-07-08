function all_node_versions
  echo "Searching..."
  set versions
  set temp_dir (mktemp -d)

  function cleanup
    rm -rf $temp_dir
  end

  trap cleanup INT TERM

  for file in (find . -type f \( -name ".nvmrc" -o -name ".tool-versions" \) -not -path "*/node_modules/*")
      set dir (dirname $file)
      if test (basename $file) = ".nvmrc"
          set node_version (cat $file | string trim | string replace -r '^v' '')
          set versions $versions $node_version
          echo $dir >> $temp_dir/$node_version
      else if test (basename $file) = ".tool-versions"
          for line in (cat $file)
              if string match -r '^nodejs ' $line > /dev/null
                  set node_version (echo $line | string split ' ' | tail -n 1)
                  set versions $versions $node_version
                  echo $dir >> $temp_dir/$node_version
              end
          end
      end
  end

  set unique_versions (printf "%s\n" $versions | sort | uniq)

  echo -n (tput cuu1) (tput el)
  set_color yellow
  echo "Unique Node.js versions found:"
  set_color normal
  for unique_version in $unique_versions
      set_color -b green
      echo $unique_version
      set_color normal
      cat $temp_dir/$unique_version | while read -l dir
          set_color cyan
          echo "  $dir"
          set_color normal
      end
  end

  cleanup
end