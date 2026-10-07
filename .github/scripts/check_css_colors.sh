#!/usr/bin/env bash
# Rejects hex colour literals in the admin stylesheets outside the tokens file.
#
# Colours belong in assets/css/tokens.css as role custom properties. Files not
# yet converted are listed in .github/css-color-allowlist.txt with their
# current literal count: a file may not gain literals, and when it loses some
# its entry must be lowered (or removed at zero), so the list only shrinks.
#
#   .github/scripts/check_css_colors.sh           check (CI)
#   .github/scripts/check_css_colors.sh --update  rewrite the allowlist from
#                                                 the current counts
#
# Comments are ignored. A literal is #rgb, #rgba, #rrggbb or #rrggbbaa not
# followed by a name character, so ID selectors such as #brando-main are not
# counted.
set -euo pipefail

cd "$(dirname "$0")/../.."

css_dir="assets/css"
tokens="assets/css/tokens.css"
allowlist=".github/css-color-allowlist.txt"

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

current=$(mktemp)
trap 'rm -f "$current"' EXIT

find "$css_dir" -type f -name '*.css' ! -path "$tokens" | LC_ALL=C sort | while read -r file; do
  n=$(count_literals "$file")
  if [ "$n" -gt 0 ]; then
    printf '%s %s\n' "$file" "$n"
  fi
done > "$current"

if [ "${1:-}" = "--update" ]; then
  {
    echo "# Hex colour literals per admin stylesheet, checked by"
    echo "# .github/scripts/check_css_colors.sh. Counts may only go down: convert"
    echo "# colours to the role tokens in assets/css/tokens.css and lower the count."
    cat "$current"
  } > "$allowlist"
  echo "Wrote $allowlist ($(wc -l < "$current" | tr -d ' ') files)."
  exit 0
fi

status=0

while read -r file n; do
  allowed=$(awk -v f="$file" '$1 == f { print $2 }' "$allowlist")
  if [ -z "$allowed" ]; then
    echo "$file: $n hex colour literal(s). Use the role tokens in $tokens (var(--brando-ink) and friends) instead." >&2
    status=1
  elif [ "$n" -gt "$allowed" ]; then
    echo "$file: $n hex colour literals, allowlist permits $allowed. Use the role tokens in $tokens for new colours." >&2
    status=1
  elif [ "$n" -lt "$allowed" ]; then
    echo "$file: down to $n hex colour literals from $allowed. Lower its count in $allowlist." >&2
    status=1
  fi
done < "$current"

while read -r file allowed; do
  case "$file" in ''|'#'*) continue ;; esac
  if ! awk -v f="$file" '$1 == f { found = 1 } END { exit !found }' "$current"; then
    echo "$file: listed in $allowlist but has no hex colour literals (or no longer exists). Remove its entry." >&2
    status=1
  fi
done < "$allowlist"

if [ "$status" -eq 0 ]; then
  total=$(awk '{ sum += $2 } END { print sum + 0 }' "$current")
  echo "CSS colour check passed: $total allowlisted literals in $(wc -l < "$current" | tr -d ' ') files."
fi

exit "$status"
