# Autocomplete for grit_auto command
function __fish_grit_auto_complete
  for file in (find ./.grit/patterns -type f)
    set filename (basename $file)
    set pattern (string split -r . $filename)[1]
    echo $pattern
  end
end

complete -c grit_auto -f
complete -c grit_auto -a "(__fish_grit_auto_complete)"
