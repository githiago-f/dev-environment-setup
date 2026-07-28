#!/bin/bash

# curl cht.sh/{language}/query+string
# curl cht.sh/{core-util}~{operation}

languages=`echo "golang lua java typescript nodejs python scala javascript zig rust" | tr ' ' '\n'`
core_utils=`echo "xargs find mv sed awk grep" | tr ' ' '\n'`
nvim=`echo "neovim" | tr ' ' '\n'`

selected=`printf "$languages\n$core_utils\n$nvim" | fzf`

if echo $nvim | grep -qs $selected; then
  cat ~/.config/nvim/vim-tools.md;
  while [ : ]; do sleep 1; done
  exit;
fi

read -p "query: " query

if echo $languages | grep -qs $selected; then
  CHT_URL="cht.sh/$selected/$(echo $query | tr ' ' '+')"
else
  CHT_URL="cht.sh/$selected~$query"
fi

curl "$CHT_URL" & while [ : ]; do sleep 1; done

