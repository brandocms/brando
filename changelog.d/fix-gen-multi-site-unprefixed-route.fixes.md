- On a multi-site installation without the CMS site, `mix brando.gen --public-route` no longer pins the unprefixed routes of a translatable resource to the installation's default language: they show each site's default language, and a prefix for a language the site does not have answers 404.
  In routes generated before, remove `assigns: %{language: "…"}` from the unprefixed `scope "/"`. In the controller, replace `language: conn.assigns.language` with `language: language(conn)` and add, above `parse_id/1` when the controller has one:
  `defp language(%{assigns: %{language: language}}), do: if(Brando.Languages.member?(language), do: language, else: raise(Ecto.NoResultsError, queryable: MyApp.Articles.Article))` and
  `defp language(_conn), do: Brando.Languages.default_language()`.
  A project with its own `priv/templates/brando.gen/controller.ex` keeps the installation's default on the unprefixed routes until that template takes `language/1` from Brando's.
