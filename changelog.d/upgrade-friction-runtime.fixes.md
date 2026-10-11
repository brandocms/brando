- **A Blueprint's own `srcset` replaces the default one**. An image or gallery
  config's `srcset` was merged into the site's `default_config.srcset`: a
  legacy flat srcset (`%{"crop_md" => "600w"}`) failed compilation as mixing
  keyed lists with size entries, and a keyed one declaring only `cropped:`
  inherited the default's `default:` list and failed on sizes it does not
  have. A flat `srcset`, or a keyed one in a config with its own `sizes`, now
  replaces the default; a keyed one on the default sizes is still merged key
  by key, so `cropped:` alone keeps the default's `default:` list.

- **Search, the command palette, the dashboard and the schedule skip types
  with no admin editor**. They kept every Blueprint with persisted
  identifiers, since every Blueprint generates `__admin_route__/2`, so a match
  on one whose application has no form route (`admin_farm_form_path/3 is
  undefined`) crashed the Search LiveView, and the dashboard's recent and
  scheduled entries could do the same.
  `Brando.Blueprint.admin_editor?/1` now checks that the router defines the
  form route. `mix brando.migrate55` says such Blueprints should set
  `persist_identifier false`.

- **Public HTML no longer carries live-preview markers, empty captions or a
  missing `og:locale`**. A multi module's or container's children were
  wrapped in `<!-- [+:C<uid>] -->` comments in every render; they are now
  added only to annotated renders (live preview, frontend edit), as block
  markers are. A picture with no title or credits no longer gets an empty
  `<figcaption>`. Pages lost `og:locale`, which read the language from Ecto's
  `__meta__`; it now comes from the page (`nb_NO` for `no`).

- **Blueprint deprecation warnings name the file and line, and legacy listing
  columns say the change is manual**. The warnings for syntax
  `mix brando.migrate54` rewrites, and for listing `field/3` and
  `template/2`, pointed only into the compiler. They now point at the
  Blueprint line, and `field/3`/`template/2` no longer send you to
  `mix brando.migrate54`, which does not rewrite them: replace them with a row
  component (`guides/blueprint_listings.md#rows`).

- **`mix brando.migrate55` completes Plural-Forms headers for locales Gettext
  does not know**. A bare `nplurals=2;` now gets the two-form rule
  `plural=(n != 1);`, with a warning to check it, and a rule missing its
  trailing `;` gets one; only other headers are left for you. A country code
  in the locale's place (`dk`) is pointed at its language
  (`did you mean da?`).

- **`mix brando.entries.resave` and `mix brando.ssg` take `--yes`, and fail
  when nobody can answer their prompt**. Run without a terminal, they read the
  closed stdin as "no" and exited 0 having done nothing. They now exit
  non-zero, saying nothing was done and to pass `--yes` (`--force` still
  works); answering "n" says so too. `mix brando.migrate_to_tenant` asks the
  same way.

- **Critical CSS is inlined again from Vite 3 and 4 manifests**. The manifest
  parser found the critical entry by its `name`, which only Vite 5+ writes, so
  a site still on Vite 3 or 4 rendered `/* no critical css */` and loaded the
  critical bundle as an ordinary stylesheet, without a warning. An entry with
  no `name` is now named by its key's basename (`js/critical.js`).
