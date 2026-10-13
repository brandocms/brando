- **A has_many multi select without `relation:` fails the compile, and
  `mix brando.migrate54` adds it** (#3169). The admin form crashed on opening
  (`Multi selects for a :has_many relation needs a relation_key and a
  relation`), though the input is static Blueprint data. The Blueprint now
  fails to compile with the input, the missing option and the value to add.
  `migrate54` adds `relation:` to a 0.53 input with only `relation_key:`,
  from the join schema's belongs_to on that key, in `inputs_for` too, and
  lists an input whose belongs_to it cannot find. In `inputs_for`, the check runs after the
  subform's schema compiles, as a warning.
- **An `:entries` input's `sources:` options are checked against the
  identifiers they apply to, and `mix brando.migrate54` drops the rest** (#3169).
  The options filter and order the identifiers the picker lists, not the
  source schema, so a 0.53 `for: [{__MODULE__, %{preload: [:categories],
  order: "asc language, asc sequence"}}]` carried over as `sources:` crashed
  the form with `column c0.sequence does not exist`. `filter:`, a non-empty
  `preload:`, other keys the identifier query does not run, and an order by
  a column identifiers lack or through an association now fail the compile,
  naming the options to write instead; so does a missing `sources:`. In
  `inputs_for` they are compile warnings. `migrate54` drops those options and says what it dropped.
  `guides/blueprint_forms.md` lists what the options apply to.
- **`mix brando.migrate54` points fragment map reads at `rendered_blocks`** (#3169).
  A fragment lost `html` in 0.54, and `@partials["newsletter"].html`, a read
  of the map `Brando.Plug.Fragment` assigns, failed every page with a
  `KeyError`. The task rewrites reads of a map the plug or a
  `get_fragments` call fills, and lists the other `…].html` map reads with
  file and line.
- **`mix brando.migrate55` lists reads of `:entries` relations** (#3169). Since 0.54
  the relation holds join rows, so `Enum.map(project.related_entries, &
  &1.entry_id)` fails with a `KeyError`. The task lists each read with file
  and line, and the fix (preload `related_entries: :identifier`, read
  `& &1.identifier.entry_id`), which `guides/blueprint_fields.md` and
  `guides/migrating_from_053.md` now show.
- **`mix brando.migrate55` writes `identifier false` on embedded Blueprints
  and rewrites `default_srcset` in asset configs** (#3169). 0.55 refuses both, which
  compiled before. An embedded Blueprint's identifier becomes `identifier
  false`; `default_srcset:` in an image `cfg`, which Brando ignored there,
  becomes `srcset: %{default: […]}`, or is removed beside a `srcset:`. The
  `unknown image config fields: [:default_srcset]` error now names the
  replacement too.
