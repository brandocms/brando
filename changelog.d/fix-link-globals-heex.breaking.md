- In a HEEx module template, a link global in `@globals` is its `Brando.Content.Var`, not its URL string. Printing it, in text or an attribute, still gives the URL.
  Where a template uses one as a string (`<>`, `String` functions, a comparison), pass it through `Brando.Villain.Filters.link_url/1` first.
