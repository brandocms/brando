- **`mix brando.gettext.reconcile` reconciles Gettext catalogs in one step.**
  After the 0.55 source tasks it extracts, merges each Gettext backend's
  existing locales (and only those, with the `Plural-Forms` header each
  locale's catalogs declare), fills empty translations from sibling catalogs
  as `scripts/sync_gettext.sh` did, and deletes the 0.53
  `<domain>_<schema>_naming`, `_forms` and `_listings` catalogs the merge
  leaves without messages. It reports per Blueprint domain and locale the
  translations carried over and filled, and lists the ones dropped because
  their msgid is no longer in the source (on a 0.53 site, mostly the old
  generator's action labels). `--dry-run` reports without writing. It
  replaces the `gettext.extract`, per-directory `gettext.merge`,
  `sync_gettext.sh` and cleanup commands, and `mix brando.migrate55` now
  names it as the Gettext step.
