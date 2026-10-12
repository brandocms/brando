- **`mix brando.migrate54` writes the row component for legacy listing
  columns.** A 0.53 listing's `field` and `template` columns render nothing
  since 0.54. The task now replaces them with `component
  &__MODULE__.listing_row/1` and appends a `listing_row/1` to the Blueprint,
  with the `Listings.Components` imports it uses: an `:image` field becomes
  `<.cover>` (its `padded` class a flag), a `:url` field `<.url>`, and a
  Liquid template whose only link goes to the entry's admin update form
  becomes `<.update_link>`, the markup before the link in its `:before`
  slot. `{{ entry.a.b }}` becomes `{@entry.a && @entry.a.b}` and
  `{% if entry.x %}` an `:if` on the element it wraps (text gets a
  `<span>`). `field :language, :language` columns are dropped, since a
  listing shows only the content language, and so are inline `<svg>` icons
  in badges, which 0.55's `.badge` puts on a line of their own; the notice
  lists both. A listing with any other column, Liquid or link is left as it
  is and named with file and line.
