- **The admin search no longer crashes on the first search after the server
  starts in development.** It turned the sort and status options into atoms
  with `String.to_existing_atom/1`, and before anything had loaded the module
  that names `:relevance`, joining the search page raised. An empty search
  index now says so, with a link to Utilities → Search index for those who
  may open it, instead of "Nothing matches"; two content types with the same
  plural (`Articles.Category` and `Menu.Category`) are told apart by their
  domain in the type filter; the browser tab is titled "Search: …" before the
  page connects too; and text variables that hold only an address
  (`#content`, `/about`, `https://…`), as modules made before link variables
  kept their links, are no longer indexed, so they stop showing up in result
  snippets. Rebuild the index to drop them from existing documents.

- **A listing's sort menu shows the order its rows are in.** A menu link
  carries the default listing's `query.order`, often
  `[{:asc, :sequence}, …]`, and when none of the listing's sorts had that
  order the menu named the first sort ("Title ↓") over rows in their stored
  order, and hid the drag handles. Such an order now reads "Manual order"
  when it sorts by `sequence` (with the handles) and "Custom order"
  otherwise. The selection bar of a listing with nothing selected is now
  hidden from the keyboard and screen readers as well as from view; it was
  only transparent, so its "0 selected" and Actions could still be reached.

- **The block editor no longer announces every block as changed.** Each
  block's unsaved-changes dot was only transparent when the block had no
  changes, so assistive technology read "Block has changes" on every block,
  and the Norwegian "Blokken har oppdateringer" ("the block has updates")
  read as if every block were behind its module, which `mix brando.doctor`
  and Utilities contradicted. The dot is now hidden until the block has
  unsaved changes and is named "Block has unsaved changes" ("Blokken har
  ulagrede endringer"). A block's drag handle has an accessible name, and
  the keyboard shortcut sheet lists undo and redo for typing.
