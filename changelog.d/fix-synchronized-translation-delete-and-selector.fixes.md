- A synchronized translation deleted for good, from the trash or in a content type without one, leaves its group, and its language can be translated again; one in the trash keeps its place until it is restored, and creating its language meanwhile says it is in the trash.
  Run `mix brando.gen.migrations` for `brando_238`, then `mix brando.migrate` before the new release starts.
  In a release, run `bin/my_app eval "MyApp.ReleaseTasks.migrate()"` from the new release.
- Deleting the source of synchronized translations, from the listing or by undoing a proposal, says why it is refused, and that a translation in the trash counts too.
- Recovering a content import no longer deletes an entry made the source of synchronized translations since, and takes an entry it deletes out of its translation group.
