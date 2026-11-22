- `Brando.Content.Blocks.update_identifier_links_and_rerender/2` is removed; nothing in Brando called it.
  A project that calls it after changing an entry outside a Blueprint's generated update function: call `Brando.Content.update_identifier(schema, entry)`, which rewrites the stored links when the entry's URL changed, then `Brando.Content.Blocks.enqueue_entry_cascade(schema, entry, identifier.id)` with the identifier it returns, which queues the re-render of the entries that link to it. Saving through the generated update function already does both.

- `Brando.Captions.preview_html/1` is removed: `Brando.Captions.safe_preview/2` previews a caption as `Brando.Captions.rich_html/1` prints it.
  A project that calls `preview_html/1`: call `rich_html/1`.
