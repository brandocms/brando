## Datasources (TODO)

```elixir
datasources do
  datasource :all_posts_from_year do
    type :list
    list &__MODULE__.list_all/3
  end

  datasource :featured_entries do
    type :selection
    list &__MODULE__.list_featured/3
    get &__MODULE__.get_featured/1
  end
end

def list_all(_schema, _language, _vars) do
  Context.list_photos(%{
    status: :published,
    preload: [:listing_image],
    order: "asc sequence, desc inserted_at"
  })
end

def list_featured(schema, _language, _vars) do
  Brando.Content.list_identifiers(schema, %{})
end

def get_featured(identifiers) do
  Brando.Content.get_entries_from_identifiers(
    identifiers,
    [:listing_image]
  )
end

```

#### List

##### Using the datasource dynamically

If you choose to parse and render the Villain field on every page load (or cache it)
by using `<.render_data conn={@conn} entry={@entry} />`, the datasource will receive
an extra `response` key in `vars` in its `list` callback:

    list :by_category, fn module, language, %{"response" => %{params: %{category_slug: slug}}} ->
      {:ok, Repo.all(from t in module, where: t.category_slug == ^slug)}
    end

The `category_slug` key in params here is populated due to the route matching in our `router.ex`