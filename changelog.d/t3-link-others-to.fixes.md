- **Menus and links in html vars follow an entry's new address.** When an
  entry's address changed (a new permalink, say), a menu item linking to it
  kept the old address until a menu was saved, and a rich-text link to it in
  a block's html var or a table cell kept its old `href`, its block never
  re-rendered. Saving the entry now rebuilds the cached menus that link to it
  and rewrites those links, the way links in block text and rich-text fields
  already were.
