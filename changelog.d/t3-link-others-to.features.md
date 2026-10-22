- **Link to an entry that has no page here but does have a destination.**
  `absolute_url ..., only: %{type: :full_case}, link_others_to: :external_link`
  names the field that holds where links to the entries `only:` excludes go,
  a case that only links to the client's site, say. The entry link picker,
  for link vars and menu items, and the rich-text link dialog list those
  entries, marked with an arrow and the destination's host. Link vars, menu
  items and rich-text links to them render the destination, and follow it
  when the field changes or the entry gets a page here.
  `__absolute_url__/1`, `__has_url__/1` and `__url_filter__/0` are unchanged,
  so sitemaps, the SEO audit and structured data still leave the entries
  out. `brando_220` adds `content_identifiers.external_url` in every
  environment; run `mix brando.gen.migrations` and `mix brando.migrate`.
  Existing entries get their destination when saved, or with **Sync
  identifiers** in Utilities. `Brando.Content.Identifier.link_url/1` gives an
  identifier's link destination.
