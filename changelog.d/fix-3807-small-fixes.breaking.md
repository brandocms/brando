- `Brando.Content.Blocks.update_identifier_links_and_rerender/2` is removed; nothing in Brando called it.
  A project that calls it: call `update_identifier_links_in_refs/2` and `update_identifier_links_in_html_vars/2` from the same module instead. Changing an entry's URL already updates its links (`Brando.Content.update_identifier/2`).

- `Brando.Captions.preview_html/1` is removed: `Brando.Captions.safe_preview/2` previews a caption as `Brando.Captions.rich_html/1` prints it.
  A project that calls `preview_html/1`: call `rich_html/1`.
