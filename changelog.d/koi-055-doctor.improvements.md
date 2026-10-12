- **`mix brando.entries.resave` and `mix brando.identifiers.sync` say that a
  running server keeps its cache.** They write to the database, while a
  server already running keeps serving the pages it cached (pages are cached
  without expiry), so the resaved content seemed not to arrive. Both now end
  with: restart running servers, or use Configuration → Cache → Empty all
  caches in the admin.

- **`mix brando.upgrade.snapshot urls` picks heavy entries and can skip the
  old site's 404s.** For each Blueprint other than pages it takes the entry
  with the most blocks in each language instead of the first by id. With
  `--base-url`, the old site's address, it asks the old site for every entry
  URL, leaves out those answered with 404 (a language whose routes are off)
  and tries the next-heaviest entry, listing what it left out.

- **`mix brando.doctor` and `scripts/prepare_055_deps.exs` check the Node on
  the PATH.** Both print `node --version` and warn on an odd release (23, say,
  which pnpm and yarn refuse for Vite 8 and the asset packages), on one older
  than Brando is tested on, and on a 22 before 22.12, saying to use Node 22
  (or another even LTS major ≥ 22). The doctor's new Node.js check is skipped
  in a release. The tested major lives in `Brando.Toolchain`.
