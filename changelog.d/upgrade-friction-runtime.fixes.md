- A Blueprint's flat `srcset`, or a keyed one in an image config with its own `sizes`, replaces the
  site's default srcset instead of being merged into it
  ([#3161](https://github.com/brandocms/brando/pull/3161)).

- Search, the command palette, the dashboard and the schedule skip content types with no admin form
  route instead of crashing ([#3161](https://github.com/brandocms/brando/pull/3161)).

- Public HTML no longer carries live-preview comments around a multi module's or container's
  children or an empty `<figcaption>`, and pages have `og:locale` again
  ([#3161](https://github.com/brandocms/brando/pull/3161)).

- Blueprint deprecation warnings name the Blueprint's file and line
  ([#3161](https://github.com/brandocms/brando/pull/3161)).
  Replace listing `field/3` and `template/2` columns with a row component
  (`guides/blueprint_listings.md#rows`); `mix brando.migrate54` writes one for the columns it can
  convert.

- `mix brando.migrate55` completes `Plural-Forms` headers for locales Gettext does not know
  ([#3161](https://github.com/brandocms/brando/pull/3161)).

- `mix brando.entries.resave` and `mix brando.ssg` exit non-zero when run without a terminal and
  without `--yes` ([#3161](https://github.com/brandocms/brando/pull/3161)).
  Pass `--yes` when you run them from a script.

- Critical CSS is inlined again from Vite 3 and 4 manifests
  ([#3161](https://github.com/brandocms/brando/pull/3161)).
