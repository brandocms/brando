- A static build follows a redirect only within its own origin, and re-sends the signed SSG header only there; a redirect to any other scheme, host or port fails that URL with no request.
  Write the target of a redirect on a path your SSG module lists as a relative path, or take the path off the list.
  Make a custom `:fetcher` honour `redirect: false` and return the redirect with its `:headers`.
