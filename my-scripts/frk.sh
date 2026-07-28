#!/bin/bash 

if [ ! -f "pom.xml" ]; then
  echo "ERROR: no pom.xml on the root directory"
  exit 1;
fi

opts="--enable-native-access=ALL-UNNAMED --sun-misc-unsafe-memory-access=allow"


commands=`MAVEN_OPTS="$opts" mvn help:describe -Dcmd=install | grep '^*' | tr '* ' ' '`
command=`printf "$commands" | fzf`
command="${command%%:*}"

MAVEN_OPTS="$opts" mvn $command

