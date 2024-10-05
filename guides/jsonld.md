## JSON-LD

### Example

#### Adding breadcrumbs

In your controller:

```elixir 
  {:ok, exhibition} = Exhibitions.get_exhibition(%{matches: %{slug: slug}})

  breadcrumbs = [
    {gettext("Home"), Routes.page_url(conn, :index, [])},
    {"Exhibitions", Routes.exhibition_url(conn, :index, [])},
    {exhibition.title, Routes.exhibition_url(conn, :show, exhibition.id, exhibition.slug)}
  ]

  conn
  |> put_json_ld(:breadcrumbs, breadcrumbs)
  # |> ...
```

#### Adding your own entity

In your blueprint:

```elixir

  json_ld_schema JSONLD.Schema.CreativeWork do
    field :author, :identity
    field :copyrightHolder, :identity
    field :creator, :identity
    field :publisher, :identity

    field :copyrightYear, :integer, & &1.inserted_at.year
    field :dateModified, :datetime, & &1.updated_at
    field :datePublished, :datetime, & &1.inserted_at

    field :description, :string, &fallback([&1.meta_description, {:strip_tags, &1.intro}])
    field :headline, :string, & &1.title
    field :name, :string, & &1.title
    field :image, :image, & &1.cover
    field :inLanguage, :language
    field :keywords, :string, &__MODULE__.keywords(&1.case_categories)
    field :mainEntityOfPage, :current_url
    field :url, :current_url
  end
```

In your controller:

```elixir
  {:ok, case} = Cases.get_case(%{matches: %{slug: slug}})

  conn
  |> assign(:case, case)
  |> put_title(case.title)
  |> put_meta(Cases.Case, case)
  |> put_json_ld(Cases.Case, case)
  # |> put_json_ld(:breadcrumbs, breadcrumbs)
  |> put_section("case")
  |> render(:detail)
```