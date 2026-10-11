- **A Blueprint's own `srcset` replaces the default one**. An image or gallery
  config's `srcset` was merged into the site's `default_config.srcset`: a
  legacy flat srcset (`%{"crop_md" => "600w"}`) failed compilation as mixing
  keyed lists with size entries, and a keyed one declaring only `cropped:`
  inherited the default's `default:` list and failed on sizes it does not
  have. A declared `srcset` now replaces the default whole, as `sizes` does.

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
  `template/2`, pointed only into the compiler. They now point at the Blueprint line, and
  `field/3`/`template/2` no longer send you to `mix brando.migrate54`, which
  does not rewrite them: replace them with a row component
  (`guides/blueprint_listings.md#rows`).
