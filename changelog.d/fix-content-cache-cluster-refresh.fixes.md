- With several nodes, a save of identity, SEO, globals, palettes or menus now refreshes every node's copy of them, and a save of any entry evicts its schema's cached queries on every node; before, only the saving node was refreshed until a restart or the query cache's expiry.

- With several nodes, a rendered entry no longer keeps old identity, globals, menus, modules, containers, palettes or fragments when its render job runs on a node that had not yet heard of the change.

- With group authorization, an admin whose groups may not read menus, global sets or identities no longer leaves the site's menus, globals or identity empty for every visitor by opening a page or preview while their cache is empty; the cache is filled with every row, as a save's refresh already did.
