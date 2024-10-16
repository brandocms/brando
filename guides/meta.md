## Meta

### Blueprint

Meta information is built from the blueprint:

```elixir
    use Brando.Blueprint,
    # ...

    meta_schema do
      field ["description", "og:description"], &Brando.HTML.truncate(&1, 155)
      field ["title", "og:title"], & &1.title
      field ["title", "og:title"], &fallback(&1, [:meta_title, {:strip_tags, :title}])
      field "og:image", & &1.meta_image
      field "og:locale", &encode_locale(&1.language)
    end
```

  The first argument is the key name and can also be supplied as a list of keys where
  multiple keys will share the same value.

  The second argument should be a function that will receive the entry as the first param
  and return the processed value.

  There are also some built in helpers you can use:

  - `fallback(data, keys)` tries `keys` until it gets a value, so in the above example it
    first tries to get `data.meta_title`, if that fails it tries `data.title`, but will strip
    it for HTML tags. For nested access, you can pass a path as a list: `[[:map, :first, :second], :fallback_here]`

  -`encode_locale(language)` converts the locale to a format facebook/opengraph understands.

### Controller

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