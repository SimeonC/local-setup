function claude --wraps=claude --description 'Claude with kaleidoscope watch of files'
    open --background "kaleidoscope://changeset?path=$PWD" &
    command claude $argv
end
