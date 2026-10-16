#!/usr/bin/env bash
# Rejects pixel font sizes in the admin stylesheets: `font-size: 12px`, the
# size in a `font` shorthand (`font: 500 12px/18px …`; a pixel line-height
# after the slash is fine), `@fontsize 12px` and `@font mono 12px`, including
# inside clamp().
#
# Every admin font size is a step of the type scale, `theme.text` in
# assets/europa.json5. assets/css/tokens.css sets --brando-text-2xs …
# --brando-text-6xl from it, and every other stylesheet uses those
# (`font-size: var(--brando-text-sm)`), so an application's europa.json5
# retunes the admin's type. Relative sizes (em, %, inherit) are not checked,
# and neither are Europa's named responsive sizes (`@fontsize input`, from
# theme.typography.sizes), which the editor's content and inputs use.
#
#   .github/scripts/check_css_font_sizes.sh
#
# Comments are ignored.
set -euo pipefail

cd "$(dirname "$0")/../.."

css_dir="assets/css"

count_sizes() {
  # The whole file as one line, comments removed, so a declaration that spans
  # lines is checked whole.
  awk '
    { text = text " " $0 }
    END {
      out = ""
      while (length(text) > 0) {
        start = index(text, "/*")
        if (start == 0) { out = out text; break }
        out = out substr(text, 1, start - 1)
        text = substr(text, start + 2)
        end = index(text, "*/")
        if (end == 0) break
        text = substr(text, end + 2)
      }
      rest = out
      while (match(rest, /font-size[ \t]*:[^;}]*[0-9]px/)) {
        count++
        rest = substr(rest, RSTART + RLENGTH)
      }
      rest = out
      while (match(rest, /@fontsize[ \t]+[0-9.]+px|@font[ \t]+[a-zA-Z_-]+[ \t]+[0-9.]+px/)) {
        count++
        rest = substr(rest, RSTART + RLENGTH)
      }
      # A font shorthand: the size comes before the slash, the line-height
      # after it, so only the part before the first slash is checked.
      rest = out
      while (match(rest, /(^|[^a-zA-Z0-9_-])font[ \t]*:[^;}]*/)) {
        value = substr(rest, RSTART, RLENGTH)
        slash = index(value, "/")
        if (slash > 0) value = substr(value, 1, slash - 1)
        if (value ~ /[0-9]px/) count++
        rest = substr(rest, RSTART + RLENGTH)
      }
      print count + 0
    }
  ' "$1"
}

status=0
files=0

while read -r file; do
  files=$((files + 1))
  n=$(count_sizes "$file")
  if [ "$n" -gt 0 ]; then
    echo "$file: $n pixel font size(s). Use a step of the type scale, var(--brando-text-2xs) to var(--brando-text-6xl) (theme.text in assets/europa.json5, set in assets/css/tokens.css)." >&2
    status=1
  fi
done < <(find "$css_dir" -type f -name '*.css' | LC_ALL=C sort)

if [ "$status" -eq 0 ]; then
  echo "CSS font size check passed: no pixel font sizes in $files stylesheets."
fi

exit "$status"
