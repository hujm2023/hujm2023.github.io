#!/bin/zsh
# remove old docs
rm -rf public docs
# use PaperMod theme and generate static files to public folder
hugo -t PaperMod
# move public folder to docs folder
mv public docs

# push to remote
git add .
time=$(date "+%Y-%m-%d %H:%M:%S")
git commit -m "$time"
git push -f origin even_source