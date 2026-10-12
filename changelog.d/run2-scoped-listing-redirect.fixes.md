- **Saving an entry with blocks returns to a scoped listing.** After a save
  whose target is the listing, an entry with blocks went to
  `admin_live_path` whatever the Blueprint's `router_scope`, so for a schema
  routed in a `scope …, as: :menu` the form crashed after saving. It now
  uses the Blueprint's own list route, as entries without blocks already
  did.
