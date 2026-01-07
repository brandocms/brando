#!/bin/bash

# Directory containing .po files
DIRECTORY="${1:-.}"

# Loop over all .po files in the specified directory
for file in "$DIRECTORY"/*.po; do
    echo "Processing file: $file..."

    # Use awk to find all msgid entries with an empty msgstr after
    awk -v file="$file" '
        /^msgid / { msgid_line = NR; msgid = $0 }
        /^msgstr ""$/ {
            empty_msgstr_line = NR
            msgid_text = msgid
            # Remove msgid " and trailing quote
            gsub(/^msgid "/, "", msgid_text)
            gsub(/"$/, "", msgid_text)
            print empty_msgstr_line ":" msgid_text
        }
    ' "$file" | while IFS=: read -r empty_msgstr_line msgid; do
        echo "Empty msgstr found for msgid \"$msgid\" at line $empty_msgstr_line in $file."

        # Loop over other .po files to find a non-empty msgstr for this msgid
        found_msgstr=""
        for other_file in "$DIRECTORY"/*.po; do
            # Skip the current file
            [ "$other_file" == "$file" ] && continue

            # Look for the same msgid in the other file
            found_msgstr=$(awk -v msgid="$msgid" '
                BEGIN { found = 0 }
                $0 == "msgid \"" msgid "\"" { found = 1; next }
                found && /^msgstr / {
                    if ($0 != "msgstr \"\"") {
                        gsub(/^msgstr "/, "", $0);
                        gsub(/"$/, "", $0);
                        print $0;
                        exit
                    }
                    found = 0
                }
            ' "$other_file")

            # If a non-empty msgstr is found, replace it in the original file
            if [ -n "$found_msgstr" ]; then
                # Escape any & characters in found_msgstr
                safe_msgstr=$(echo "$found_msgstr" | sed 's/&/\\&/g')
                echo "Found translation for \"$msgid\" in $other_file: \"$safe_msgstr\""
                gsed -i "${empty_msgstr_line}s/msgstr \"\"/msgstr \"$safe_msgstr\"/" "$file"
                break
            fi
        done

        # Message if no translation was found in other files
        if [ -z "$found_msgstr" ]; then
            echo "No translation found for \"$msgid\" in other files."
        fi
    done
done

echo "Translation copy complete."
