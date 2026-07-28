find="find";
if command -v fd 2>&1 >/dev/null; then
  find="fd";
elif command -v fdfind 2>&1 >/dev/null; then
  find="fdfind";
fi

projects=`$find -d 1 . ~/projects | grep -v 'key-secret'`
configs=`$find -d 1 ~/.config/ | awk '{print ENVIRON["HOME"] "/.config/" $1}'`
dir=`printf "$projects\n$configs" | fzf`

cd $dir

