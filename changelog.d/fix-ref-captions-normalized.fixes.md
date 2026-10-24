- A video or picture ref's caption emptied in the editor, formatting and all, is stored as no caption, so the placement shows the asset's own title again, and markup the editor can't make is stripped, as gallery captions are.

- A video ref's caption names the video in structured data (JSON-LD) as plain text, its paragraphs a space apart, instead of with its markup or as an empty `<p></p>`.

- Structured data (JSON-LD) escapes `<` and `/` in its script tags, so a video's title or caption, or any other name, holding `</script>` can no longer end the tag and inject script into the public page.
