- **Editing a block with footnotes keeps the live preview's notes numbered.**
  A block patched into the preview on its own carried its note references
  raw, since notes are numbered and collected across the whole page. Such a
  block now renders the whole page.

- **A live preview that missed block edits gets them back.** Block edits
  are patched into the preview page and are not in its cached copy, so a
  page that reconnected after missing some, or was reloaded (a standalone
  preview window refreshed, say), showed the page without them until the
  next full render. The page now tells the server how many it has applied
  when it joins; when that is behind, the form renders the whole page again
  and the drawer says the preview was refreshed.
