function grit_init
  mkdir .grit
  cd .grit
  mkdir patterns
  ln -s ~/.grit/patterns/ patterns/local
  cd ..
  npx grit init
  echo "version: 0.0.1
patterns:
  - name: github.com/getgrit/js#*
  - name: github.com/getgrit/python#*
  - name: github.com/getgrit/json#*
  - name: github.com/getgrit/hcl#*
" > .grit/grit.yaml
  echo "
*.gen.ts
*.gen.d.ts
" > .grit/.gritignore
end
