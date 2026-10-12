- **Content SEO counts a cover image as a sharing image again.** The
  "Sharing image" check expected a path but the audit carries the cover's
  image id, so every entry without a meta image failed it, covers or not, and
  the "Missing image" total counted every audited entry.

- **`mix brando.images.adopt`, the doctor and Utilities no longer recommend
  recreating every image on a copy without the media.** When none of the
  images has a file in the media folder (empty, not mounted, or never synced
  to this machine), `mix brando.images.adopt` stops with
  `No image files found under <media path>`, the doctor's Image configs check
  asks for the media instead of a recreate, and Utilities → Image sizes says
  the same and no longer highlights **Recreate changed images**. A single
  missing file is now named (`large: file missing: images/site/default/large/x.jpg`)
  where it read `large is missing`, which looked like a missing size key. The
  doctor also counts how the images that differ differ (in formats, sizes,
  missing files or dimensions), so a real config change, such as a default
  config that gained `:webp`, stands apart from files missing on this machine.

- **The doctor's robots.txt check asks the endpoint before warning.** A
  `priv/static/robots.txt` only counts when the endpoint's `Plug.Static`
  serves it: by its `only:` list (a literal, as Brando's installer and
  pre-1.7 Phoenix write it, or `static_paths/0`), its `only_matching:`, or
  for want of either. A file it never serves is mentioned under `--verbose`
  and no longer warns, and the fix names the setting the site has instead of
  `static_paths`, which sites without it went looking for.

- **An image whose `config_target` field is gone no longer prints the whole
  image and a stacktrace.** Rendering such an image (its field removed or
  renamed in the Blueprint) logged the full `%Brando.Images.Image{}` with a
  stacktrace for every image, in the middle of `mix brando.migrate` and
  `mix brando.entries.resave`. It now logs one line per target and node,
  saying what it means: `Images point at a field MyApp.Article no longer has
  (image:MyApp.Article:gallery); they use the default image config.`
  `mix brando.entries.resave` ends with the same line per target with a
  count, and `mix brando.doctor --verbose` lists the targets under Image
  configs without warning.

- **`mix brando.gen.blueprint_migration` lists the Blueprints it will write,
  not their encoded plans.** "These tasks will be run" showed one long base64
  argument per Blueprint (`brando.blueprint.apply_plan eyJk…`); it now shows
  `brando.blueprint.apply_plan MyApp.Articles.Article MyApp.Projects.Project`.
  The reviewed plans are kept under `_build` until the task writes them, and
  a plan that changed since its review is still refused.
