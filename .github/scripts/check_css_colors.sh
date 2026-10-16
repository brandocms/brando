#!/usr/bin/env bash
# Rejects hex colour literals in the admin stylesheets, tokens.css included.
#
# Every admin colour is a value in the admin's theme (`theme.colors` in
# assets/europa.json5). assets/css/tokens.css sets the role custom properties
# from it with `theme(colors.*)`, and every other stylesheet uses those roles
# (`var(--brando-ink)` and friends), so an application's europa.json5 changes
# any colour.
#
#   .github/scripts/check_css_colors.sh
#
# Comments are ignored. A literal is #rgb, #rgba, #rrggbb or #rrggbbaa not
# followed by a name character, so ID selectors such as #brando-main are not
# counted.
set -euo pipefail

cd "$(dirname "$0")/../.."

css_dir="assets/css"

count_literals() {
  awk '
    {
      line = $0
      out = ""
      while (length(line) > 0) {
        if (in_comment) {
          end = index(line, "*/")
          if (end == 0) { line = ""; break }
          line = substr(line, end + 2)
          in_comment = 0
        } else {
          start = index(line, "/*")
          if (start == 0) { out = out line; line = ""; break }
          out = out substr(line, 1, start - 1)
          line = substr(line, start + 2)
          in_comment = 1
        }
      }
      rest = out " "
      while (match(rest, /#[0-9a-fA-F]+[^0-9a-zA-Z_-]/)) {
        digits = RLENGTH - 2
        if (digits == 3 || digits == 4 || digits == 6 || digits == 8) count++
        rest = substr(rest, RSTART + RLENGTH - 1)
      }
    }
    END { print count + 0 }
  ' "$1"
}

status=0
files=0

while read -r file; do
  files=$((files + 1))
  n=$(count_literals "$file")
  if [ "$n" -gt 0 ]; then
    echo "$file: $n hex colour literal(s). Use a role from assets/css/tokens.css (var(--brando-ink) and friends); a new colour gets an entry in theme.colors in assets/europa.json5 and a role in tokens.css." >&2
    status=1
  fi
done < <(find "$css_dir" -type f -name '*.css' | LC_ALL=C sort)

if [ "$status" -eq 0 ]; then
  echo "CSS colour check passed: no hex colour literals in $files stylesheets."
fi

exit "$status"
