#!/bin/bash

COMMAND="$(basename "$0") $@"

ROOT="$HOME/.config/gallery-dl/downloads"
ARGS=("--download-archive" "$HOME/.config/gallery-dl/log")

function require() {
  which $1 &> /dev/null && return
  printf "%s required!\n" "$1" >&2
  exit 1
}

require gallery-dl
require slugify
require sort
require sponge

args=()
urls=()
files=()

i=0
while [[ $# > 0 ]]
do
  ((i++))
  if [[ "$1" =~ http* ]]
  then
    urls+=("$1")
  elif [[ "${#urls[@]}" != 0 ]]
  then
    printf "Args #%d '%s' : URLS must not precede ARGS\n" "$i" "$1" >&2
    exit 1
  else
    args+=("$1")
  fi
  shift
done

mkdir -p "$ROOT"

for ((i = 0 ; i < "${#urls[@]}" ; i++))
do
  url="${urls[i]}"
  printf "reading [%d/%d] %s\n" \
    $((i+1))                    \
    "${#urls[@]}"               \
    "$url"

  fresh=$(gallery-dl --get-urls "$url" 2>/dev/null)

  if [[ $? != 0 ]]
  then
    printf "Read error '%s' (skipping)\n" "$url" 1>&2
    continue
  fi

  printf 'found %d urls' "$(echo "$fresh" | wc -l)"
  fresh=$(echo "$fresh" | LC_COLLATE=C sort -ru)
  printf ' (%d unique)' "$(echo "$fresh" | wc -l)"

  out="$ROOT/$(slugify "$url")"
  if [ -f "$out" ]
  then
    fresh=$(
      diff --normal                                             \
        <(grep "^# " "$out" | cut -c 3- | LC_COLLATE=C sort -ru) \
        <(echo "$fresh")                                        \
      | grep "^> " | cut -c 3-                                  \
    )
    printf ' (%d added)' $(echo "$fresh" | wc -l)

    fresh=$(cat <(grep -v "^##" "$out") <(echo "$fresh") | LC_COLLATE=C sort -ru)
  fi

  if [ ! -z "$FILTER" ]
  then
    fresh=$(echo "$fresh" | grep "$FILTER")
  fi

  printf "\n-> %s\n" "$out"
  echo "$fresh" > "$out"
  files+=("$out")
done

skipped=$(( ${#urls[@]} - ${#files[@]} ))
[[ $skipped > 0 ]] && printf "Skipped %d urls\n" "$skipped" 1>&2

total=0
attempted=0
failed=0
for ((i = 0 ; i < "${#files[@]}" ; i++))
do
  list="${files[i]}"
  printf "downloading [%d/%d] %s\n" \
    $((i+1))                        \
    "${#files[@]}"                  \
    "$list"

  _total=$(cat "$list" | wc -l)
  _attempted=$(grep "^# " -v "$list" | wc -l)

  [[ -z "$DEBUG" ]] && gallery-dl "${ARGS[@]}" "${args[@]}" --input-file-comment "$list"

  _failed=$(grep "^# " -v "$list" | wc -l)

  printf "progress [%d/%d] urls %d (%d tried, %d failed) %s\n" \
    $((i+1))                                                   \
    "${#files[@]}"                                             \
    "$_total"                                                  \
    "$_attempted"                                              \
    "$_failed"                                                 \
    "$list"

  cat \
    <(printf "##\n## %s\n##\n" "$COMMAND") \
    <(LC_COLLATE=C sort -ru "$list") \
  | sponge "$list"

  ((attempted+=_attempted))
  ((total+=_total))
  ((failed+=_failed))
done

printf "total urls %d (%d tried, %d failed)\n" \
  "$total"                                     \
  "$attempted"                                 \
  "$failed"
