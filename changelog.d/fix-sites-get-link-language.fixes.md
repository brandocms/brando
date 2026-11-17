- `Brando.Sites.get_link/1` and `Brando.Sites.get_language/1` no longer crash, and `get_link` returns the link's URL as it did on 0.51; both are deprecated in favour of `get_link/2` and `get_language/2`, which take the language.
  Replace `Brando.Sites.get_link("instagram")` with `Brando.Sites.get_link(@language, "instagram")`, or read `@identity.links` from `Brando.Plug.Identity`.
