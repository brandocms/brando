- **`mix brando.migrate54` rewrites navigation item reads.** It listed
  `item.url` and `item.title` in a navigation template with the helpers to
  use instead. Inside `for item <- @navigation.items` or
  `:for={item <- @menu.items}` (and generators over such an item's `items`),
  `item.url`, `item.title` and `item.open_in_new_window` now become
  `Brando.HTML.get_menu_item_url(item)`, `get_menu_item_text(item)` and
  `get_menu_item_target_blank(item)`, and `item.items` becomes
  `item.children`, in Elixir code only (interpolations included). A file
  that also binds the name to something else, and reads outside code, are
  still listed with file and line. Run `mix format` afterwards: a rewritten
  tag can get longer than the line length.
