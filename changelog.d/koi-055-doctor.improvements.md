- **`mix brando.entries.resave` and `mix brando.identifiers.sync` say that a
  running server keeps its cache.** They write to the database, while a
  server already running keeps serving the pages it cached (pages are cached
  without expiry), so the resaved content seemed not to arrive. Both now end
  with: restart running servers, or use Configuration → Cache → Empty all
  caches in the admin.
