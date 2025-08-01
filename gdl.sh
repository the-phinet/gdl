#!/bin/bash

HEADER="## $(basename "$0") $@"

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
data=()

i=0
while [[ $# > 0 ]]
do
  ((i++))
  if [[ "$1" =~ http* ]]
  then
    data+=("$1")
  elif [[ "${#data[@]}" != 0 ]]
  then
    printf "Args #%d '%s' : URLS must not precede ARGS\n" "$i" "$1" >&2
    exit 1
  else
    args+=("$1")
  fi
  shift
done

mkdir -p "$ROOT"

for ((i = 0 ; i < "${#data[@]}" ; i++))
do
  url="${data[i]}"
  out="$ROOT/$(slugify "$url")"
  printf "reading [%d/%d] %s\n-> %s\n" \
    $((i+1))                           \
    "${#data[@]}"                      \
    "$url"                             \
    "$out"

  fresh=$(gallery-dl --get-urls "$url" 2>/dev/null)
  printf 'found %d urls' "$(echo "$fresh" | wc -l)"
  fresh=$(echo "$fresh" | LC_COLLATE=C sort -u)
  printf ' (%d unique)' "$(echo "$fresh" | wc -l)"

  if [ -f "$out" ]
  then
    fresh=$(
      diff --normal                                             \
        <(grep "^# " "$out" | cut -c 3- | LC_COLLATE=C sort -u) \
        <(echo "$fresh")                                        \
      | grep "^> " | cut -c 3-                                  \
    )
    printf ' (%d added)' $(echo "$fresh" | wc -l)

    fresh=$(cat <(grep -v "^## " "$out") <(echo "$fresh") | LC_COLLATE=C sort -u)
  fi

  if [ ! -z "$FILTER" ]
  then
    fresh=$(echo "$fresh" | grep "$FILTER")
  fi

  echo
  echo "$HEADER" >"$out"
  echo "$fresh" >>"$out"
  data[$i]="$out"
done

total=0
attempted=0
failed=0
for ((i = 0 ; i < "${#data[@]}" ; i++))
do
  urls="${data[i]}"
  printf "downloading [%d/%d] %s\n" \
    $((i+1))                        \
    "${#data[@]}"                   \
    "$urls"

  _total=$(cat "$urls" | wc -l)
  _attempted=$(grep "^# " -v "$urls" | wc -l)

  gallery-dl "${ARGS[@]}" "${args[@]}" --input-file-comment "$urls"

  _failed=$(grep "^# " -v "$urls" | wc -l)

  printf "progress [%d/%d] urls %d (%d tried, %d failed) %s\n" \
    $((i+1))                                                   \
    "${#data[@]}"                                              \
    "$_total"                                                  \
    "$_attempted"                                              \
    "$_failed"                                                 \
    "$urls"

  LC_COLLATE=C sort -u "$urls" | sponge "$urls"

  ((attempted+=_attempted))
  ((total+=_total))
  ((failed+=_failed))
done

printf "total urls %d (%d tried, %d failed)\n" \
  "$total"                                     \
  "$attempted"                                 \
  "$failed"
