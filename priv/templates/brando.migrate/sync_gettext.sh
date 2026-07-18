#!/usr/bin/env bash

set -euo pipefail

directory="${1:-.}"

if [[ ! -d "$directory" ]]; then
  printf 'Gettext directory does not exist: %s\n' "$directory" >&2
  exit 1
fi

shopt -s nullglob
po_files=("$directory"/*.po)

if (( ${#po_files[@]} == 0 )); then
  printf 'No .po files found in %s\n' "$directory"
  exit 0
fi

for file in "${po_files[@]}"; do
  printf 'Processing %s...\n' "$file"

  while IFS=: read -r empty_msgstr_line msgid; do
    found_msgstr=""
    found_in=""

    for other_file in "${po_files[@]}"; do
      [[ "$other_file" == "$file" ]] && continue

      found_msgstr=$(awk -v msgid="$msgid" '
        $0 == "msgid \"" msgid "\"" { found = 1; next }
        found && /^msgstr / {
          if ($0 != "msgstr \"\"") {
            sub(/^msgstr "/, "")
            sub(/"$/, "")
            print
            exit
          }

          found = 0
        }
      ' "$other_file")

      if [[ -n "$found_msgstr" ]]; then
        found_in="$other_file"
        break
      fi
    done

    if [[ -z "$found_msgstr" ]]; then
      printf 'No sibling translation found for "%s" in %s.\n' "$msgid" "$file"
      continue
    fi

    escaped_msgstr=$(printf '%s' "$found_msgstr" | sed 's/[\\&|]/\\&/g')
    temporary_file=$(mktemp "${file}.XXXXXX")
    sed "${empty_msgstr_line}s|^msgstr \"\"$|msgstr \"${escaped_msgstr}\"|" "$file" > "$temporary_file"
    cat "$temporary_file" > "$file"
    rm -f "$temporary_file"

    printf 'Copied "%s" from %s.\n' "$msgid" "$found_in"
  done < <(
    awk '
      /^msgid "/ {
        msgid = $0
        sub(/^msgid "/, "", msgid)
        sub(/"$/, "", msgid)
      }

      /^msgstr ""$/ && msgid != "" {
        print NR ":" msgid
      }
    ' "$file"
  )
done

printf 'Translation copy complete. Review the catalog diff before committing.\n'
