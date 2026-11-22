- `Brando.Content.Blocks.update_identifier_links_and_rerender/2` is removed; nothing in Brando called it.
  A project that calls it: call `update_identifier_links_in_refs/2` and `update_identifier_links_in_html_vars/2` from the same module instead. Changing an entry's URL already updates its links (`Brando.Content.update_identifier/2`).
