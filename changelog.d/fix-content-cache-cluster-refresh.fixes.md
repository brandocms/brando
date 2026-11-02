- With several nodes, a save of identity, SEO, globals, palettes or menus now refreshes every node's copy of them, and a save of any entry evicts its schema's cached queries on every node; before, only the saving node was refreshed until a restart or the query cache's expiry.

- With several nodes, entries rendered again for a change of identity, globals or menus no longer keep the old values when the render job runs on a node that had not yet heard of the change.
