- **Make independent** gives a translation its own copy of each gallery it shares with the source, with the same media, order and item settings: a gallery variable (in a block or among the entry's own variables) pointed at the source's gallery record, so editing it in an independent translation changed the source and every other translation. The open form's gallery variables take their copies.

- `mix brando.doctor` has a "Translation galleries" check that lists independent translations still sharing a gallery with another language version, which `mix brando.translations.split_galleries` repairs.
  Run `mix brando.translations.split_galleries` after deploying, for translations made independent before this release.
  In a release, run `bin/my_app rpc "Brando.Translations.SharedGalleries.repair()"`.
