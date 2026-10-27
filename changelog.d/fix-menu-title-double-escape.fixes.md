- Navigation menus (`menu_item`, `menu_button`, `menu_item_text` and `get_menu_item_text/1`) show a linked entry's title stored by a HEEx identifier (`identifier ~H"{@entry.title}"`) as written: `Rock & Roll` no longer shows as `Rock &amp; Roll`.
  A layout that printed the menu text with `raw/1` to avoid the double escaping prints it with `{text}` instead.
