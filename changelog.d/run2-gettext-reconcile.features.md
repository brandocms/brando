- `mix brando.gettext.reconcile` extracts and merges the Gettext catalogs in one step during the
  0.55 upgrade, carries translations over from the 0.53 `_naming`, `_forms` and `_listings`
  catalogs, deletes those once empty, and reports what it carried over and dropped
  ([#3167](https://github.com/brandocms/brando/pull/3167)).
  Run it in place of `gettext.extract`, the per-directory `gettext.merge`, `scripts/sync_gettext.sh`
  and the cleanup commands; `--dry-run` writes nothing.
