- **`mix format` keeps `Brando.Authorization`'s `types [...]` without
  parentheses.** Brando's `.formatter.exs` exported `rules` and `can` but not
  `types`, so a site with `import_deps: [:brando]` had its authorization
  module rewritten to `types([...])` on the first format. It now exports
  `types/1`, and the Blueprint `authorization key: …` option as well.
