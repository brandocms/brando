- `mix brando.install` writes what a Florist deploy needs: a `Dockerfile` and `.dockerignore`,
  `MyApp.ReleaseTasks`, a release that writes a tarball, and `.gitignore` entries
  ([#3203](https://github.com/brandocms/brando/pull/3203)).
  For an application installed earlier, run `mix brando.gen.release`.

- `mix brando.gen.site` gives CMS pages a live preview
  ([#3203](https://github.com/brandocms/brando/pull/3203)).
