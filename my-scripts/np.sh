#!/bin/bash
PROJECTS="$HOME/projects"

BASE_INITIALIZERS=`echo "java zig node go scala" | tr ' ' '\n'`

initializer=`printf "$BASE_INITIALIZERS" | fzf`
dir="$(pwd)"

function is_initializr {
  return `echo $initializer | grep -qs $@`
}

function read_def {
  default_value="$2"
  read -p "$1 [$default_value]: " var
  
  if [ -z $var ]; then
    echo $default_value
  else
    echo $var
  fi
}

if is_initializr 'java'; then
  groupId=$(read_def "Group ID" "com.example")
  artifactId=$(read_def "Artifact ID" "demo")
  archetype=$(read_def "Archetype ID" "maven-archetype-quickstart")

  cd $PROJECTS &&\
    MAVEN_OPTS="--enable-native-access=ALL-UNNAMED --sun-misc-unsafe-memory-access=allow" \
    mvn archetype:generate \
    -DgroupId=$groupId \
    -DartifactId=$artifactId \
    -DarchetypeArtifactId=$archetype \
    -DinteractiveMode=false;

  dir="$PROJECTS/$artifactId"
elif is_initializr 'zig'; then
  read -p "Project name: " project
  dir="$PROJECTS/$project"

  mkdir $dir && cd $dir && zig init
elif is_initializr 'node'; then
  read -p "Project name: " project
  read -p "Version (lts/jod): " version
  dir="$PROJECTS/$project"
  
  mkdir $dir && cd $dir && npm init -y && echo "$version" > .nvmrc
elif is_initializr 'go'; then
  read -p "Project name: " project
  dir="$PROJECTS/$project"

  mkdir $dir && \
    cd $dir && \
    go mod init github.com/githiago-f/$project
elif is_initializr 'scala'; then
  sbt new scala/scala3.g8
fi

cd $dir
