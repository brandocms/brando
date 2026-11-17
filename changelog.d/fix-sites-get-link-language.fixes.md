- `Brando.Sites.get_link/1` and `Brando.Sites.get_language/1` no longer crash; both are deprecated in favour of `get_link/2` and `get_language/2`, which take the language, and `get_link` returns the URL string that 0.51's link struct printed.
  Replace `Brando.Sites.get_link("instagram")` with `Brando.Sites.get_link(@language, "instagram")`, or loop over `@identity.links` from `Brando.Plug.Identity`.
  A template that read `.url` or `.name` on the result uses the string itself, or the link from `@identity.links`.
