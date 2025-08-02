#!/bin/bash

COMMAND="$(basename "$0") $@"

GALLERYDL="$HOME/.config/gallery-dl"
CONFIG="$GALLERYDL/config.json"
ROOT="$GALLERYDL/downloads"
ARGS=("--download-archive" "$GALLERYDL/log")

function require() {
  failed=0
  for cmd in "$@"
  do
    if ! which "$cmd" &> /dev/null
    then
      printf "%s required!\n" "$cmd" >&2
      ((failed+=1))
    fi
  done
  return $failed
}

require      \
  gallery-dl \
  slugify    \
  sort       \
  sponge     \
  jq         \
  awk        \
  sed        \
|| exit

if ! [ -f "$CONFIG" ]
then
  mkdir -p "$GALLERYDL"
  echo '{"extractor":{},"downloader":{},"output":{},"postprocessor":{}}' \
  | jq > "$CONFIG"
fi

config=$(jq ".tools.gdl // {}" <"$CONFIG" 2>/dev/null)
readarray -t filters < <(jq -r "(.filter // [])[]" <<<"$config")

[ -z "$FILTER" ] || filters+=("$FILTER")

pattern=$(printf "(%s)|" "${filters[@]}")
pattern=$(<<<"${pattern%|}" sed 's;\\;\\\\;g')

tempfile=$(mktemp)
trap 'rm -f "$tempfile"' EXIT

awk_filter_code='
  BEGIN {
    old = 0; fail = 0; pass = 0
  }
  {
    if ($0 ~ /^# /) {
      old++
    } else if (p != "" && $0 ~ p) {
      fail++
      $0 = "# " $0
    } else {
      pass++
    }
    print $0
  }
  END {
    printf "%d %d %d", old, fail, pass > "/dev/stderr"
  }
'

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

  printf 'found %d urls' "$(awk 'END {print NR}' <<<"$fresh")"
  fresh=$(echo "$fresh" | LC_COLLATE=C sort -ru)
  printf ' (%d unique)' "$(awk 'END {print NR}' <<<"$fresh")"

  out="$ROOT/$(slugify "$url")"
  if [ -f "$out" ]
  then
    fresh=$(
      diff --normal                                             \
        <(grep "^# " "$out" | cut -c 3- | LC_COLLATE=C sort -ru) \
        <(echo "$fresh")                                        \
      | grep "^> " | cut -c 3-                                  \
    )

    fresh=$(cat <(grep -v "^##" "$out") <(echo "$fresh") | LC_COLLATE=C sort -ru)
  fi

  fresh=$(awk -v p="$pattern" "$awk_filter_code" <<<"$fresh" 2> "$tempfile")
  stats=( $( <"$tempfile" ) )
  skip_old=${stats[0]}
  skip_new=${stats[1]}
  added=${stats[2]}

  [[ $skip_old > 0 ]] && printf " (%d skipped)"  "$skip_old"
  [[ $skip_new > 0 ]] && printf " (%d filtered)" "$skip_new"

  [[ $added == 0 ]] && printf "Nothing to do. (skipping)\n" && continue

  printf " (%d added)\n-> %s\n" "$added" "$out"
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

  _total=$(wc -l < "$list")
  _attempted=$(grep -c "^# " -v "$list")

  [[ -z "$DEBUG" ]] && gallery-dl "${ARGS[@]}" "${args[@]}" --input-file-comment "$list"

  _failed=$(grep -c "^# " -v "$list")

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
