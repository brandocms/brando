- On a multi-site installation without the CMS site, `mix brando.gen --public-route` no longer pins the unprefixed routes of a translatable resource to the installation's default language: they show each site's default language.
  In routes generated before, remove `assigns: %{language: "…"}` from the unprefixed `scope "/"`, and in the controller replace `language: conn.assigns.language` with `language: language(conn)`, adding
  `defp language(%{assigns: %{language: language}}), do: language` and
  `defp language(_conn), do: Brando.Languages.default_language()`.
