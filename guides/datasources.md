## Datasources (TODO)

#### List

##### Using the datasource dynamically

If you choose to parse and render the Villain field on every page load (or cache it) 
by using `<.render_data conn={@conn} entry={@entry} />`, the datasource will receive
an extra key in `vars` in its `list` callback:

    list :by_category, fn module, language, %{"response" => %{params: %{category_slug: slug}}} ->
      {:ok, Repo.all(from t in module, where: t.category_slug == ^slug)}
    end

The `category_slug` key in params here is populated due to the route matching in our `router.ex`