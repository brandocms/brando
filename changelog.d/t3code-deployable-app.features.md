- **A new application deploys with Florist without copying files by hand.**
  `mix brando.install` writes Brando's `Dockerfile` and `.dockerignore` when
  the application has none, `MyApp.ReleaseTasks`, whose `migrate/0` Florist
  runs, and a release with `steps: [:assemble, :tar]` for the tarball Florist
  copies out of the image. An existing Dockerfile is kept, with a notice of
  what Brando's build needs that it lacks; an existing `.dockerignore` gets
  the exclusions it misses, the `.envrc*` files with secrets among them (with
  `!` exceptions, a notice instead); an existing ReleaseTasks or release is
  kept, with a notice when it has no `migrate/0` or writes no tarball.
  `.gitignore` gets what a Brando application builds, uploads or downloads:
  the asset projects' `node_modules` and Yalc copies, the builds in
  `priv/static`, `/media/`, `/log/`, and Florist's `/release-archives/` and
  `/sql/`. `mix brando.gen.release` is now needed only for applications
  installed earlier, and notices an existing release that writes no tarball.
  See "Release helpers", "Ignored files" and "The Docker build" in the
  deployment guide.

- **`mix brando.gen.site` gives CMS pages a live preview.** The application's
  `LivePreview` gets a `preview_target` for `Brando.Pages.Page` that renders
  with the generated `CMS.PageHTML` and `CMS.Layouts`, with the identity,
  navigation and footer partials the page controller assigns. The bare module
  `brando.install` writes is replaced; a customized one gets a notice with the
  target to add.
