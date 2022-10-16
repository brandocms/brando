defmodule Brando.Content do
  @moduledoc """
  Interface to Villain HTML editor.

  ### Available variables when rendering

    - `{{ entry.<key> }}`
    Gets `<key>` from currently rendering entry. So if we are rendering a `%Page{}` and we
    want the `meta_description` we can do `{{ entry.meta_description }}

    - `{{ links.<key> }}`
    Gets `<key>` from list of links in the Identity configuration.

    - `{{ globals.<category_key>.<key> }}`
    Gets `<key>` from `<category_key>` in list of globals in the Identity configuration.

    - `{{ forloop.index }}`
    Only available inside for loops or modules with `multi` set to true. Returns the current index
    of the for loop, starting at `1`

    - `{{ forloop.index0 }}`
    Only available inside for loops or modules with `multi` set to true. Returns the current index
    of the for loop, starting at `0`

    - `{{ forloop.count }}`
    Only available inside for loops or modules with `multi` set to true. Returns the total amount
    of entries in the for loop

  """
  use Brando.Query
  import Ecto.Query

  alias Brando.Content.Module
  alias Brando.Content.Palette
  alias Brando.Content.Template
  alias Brando.Content.Var
  alias Brando.Villain

  query :list, Module, do: fn query -> from(q in query) end

  filters Module do
    fn
      {:name, name}, query ->
        from(q in query, where: ilike(q.name, ^"%#{name}%"))

      {:class, class}, query ->
        from(q in query, where: ilike(q.class, ^"%#{class}%"))

      {:ids, ids}, query ->
        from(q in query, where: q.id in ^ids)

      {:namespace, namespace}, query ->
        query =
          from(t in query,
            order_by: [asc: t.sequence, asc: t.id, desc: t.updated_at]
          )

        namespace =
          (String.contains?(namespace, ",") && String.split(namespace, ",")) || namespace

        case namespace do
          "all" ->
            query

          namespace_list when is_list(namespace_list) ->
            from(t in query, where: t.namespace in ^namespace_list)

          _ ->
            from(t in query, where: t.namespace == ^namespace)
        end

      {:datasource, datasource}, query ->
        from q in query, where: q.datasource == ^datasource

      {:datasource_module, datasource_module}, query ->
        from q in query, where: q.datasource_module == ^datasource_module

      {:datasource_type, datasource_type}, query ->
        from q in query, where: q.datasource_type == ^datasource_type

      {:datasource_query, datasource_query}, query ->
        from q in query, where: q.datasource_query == ^datasource_query
    end
  end

  query :single, Module, do: fn query -> from(q in query) end

  matches Module do
    fn
      {:id, id}, query ->
        from(t in query, where: t.id == ^id)

      {:name, name}, query ->
        from(t in query,
          where: t.name == ^name
        )

      {:namespace, namespace}, query ->
        from(t in query,
          where: t.namespace == ^namespace
        )
    end
  end

  mutation :create, Module do
    fn entry ->
      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        "brando:modules",
        {entry, [:module, :created]}
      )

      {:ok, entry}
    end
  end

  mutation :update, Module do
    fn entry ->
      Villain.update_module_in_fields(entry.id)

      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        "brando:modules",
        {entry, [:module, :updated]}
      )

      {:ok, entry}
    end
  end

  mutation :delete, Module
  mutation :duplicate, {Module, change_fields: [:name, :class]}

  @doc """
  Find module with `id` in `modules`
  """
  def find_module(modules, id) do
    modules
    |> Enum.find(&(&1.id == id))
    |> case do
      nil -> {:error, {:module, :not_found, id}}
      mod -> {:ok, mod}
    end
  end

  ## Palettes
  ##

  query :list, Palette, do: fn query -> from(q in query) end

  filters Palette do
    fn
      {:name, name}, query ->
        from(q in query, where: ilike(q.name, ^"%#{name}%"))

      {:key, key}, query ->
        from(q in query, where: ilike(q.key, ^"%#{key}%"))

      {:color, color}, query ->
        from q in query, where: jsonb_contains(q, :colors, [%{hex_value: color}])

      {:namespace, namespace}, query ->
        namespace =
          (String.contains?(namespace, ",") && String.split(namespace, ",")) || namespace

        case namespace do
          "all" ->
            query

          namespace_list when is_list(namespace_list) ->
            from(t in query, where: t.namespace in ^namespace_list)

          _ ->
            from(t in query, where: t.namespace == ^namespace)
        end
    end
  end

  query :single, Palette, do: fn query -> from(q in query) end

  matches Palette do
    fn
      {:id, id}, query ->
        from(t in query, where: t.id == ^id)

      {:key, key}, query ->
        from(t in query,
          where: t.key == ^key
        )

      {:namespace, namespace}, query ->
        from(t in query,
          where: t.namespace == ^namespace
        )
    end
  end

  mutation :create, Palette do
    fn entry ->
      Brando.Cache.Palettes.set()

      {:ok, entry}
    end
  end

  mutation :update, Palette do
    fn entry ->
      Villain.update_palette_in_fields(entry.id)
      Brando.Cache.Palettes.set()

      {:ok, entry}
    end
  end

  mutation :delete, Palette
  mutation :duplicate, {Palette, change_fields: [:name, :key]}

  @doc """
  Find palette with `id` in `palettes`
  """
  def find_palette(palettes, id) do
    palettes
    |> Enum.find(&(&1.id == id))
    |> case do
      nil -> {:error, {:palette, :not_found, id}}
      palette -> {:ok, palette}
    end
  end

  ## Templates
  ##

  query :list, Template, do: fn query -> from(q in query) end

  filters Template do
    fn
      {:name, name}, query ->
        from(q in query, where: ilike(q.name, ^"%#{name}%"))

      {:namespace, namespace}, query ->
        query =
          from(t in query,
            order_by: [asc: t.sequence, asc: t.id, desc: t.updated_at]
          )

        namespace =
          (String.contains?(namespace, ",") && String.split(namespace, ",")) || namespace

        case namespace do
          "all" ->
            query

          namespace_list when is_list(namespace_list) ->
            from(t in query, where: t.namespace in ^namespace_list)

          _ ->
            from(t in query, where: t.namespace == ^namespace)
        end
    end
  end

  query :single, Template, do: fn query -> from(q in query) end

  matches Template do
    fn
      {:id, id}, query ->
        from(t in query, where: t.id == ^id)

      {:namespace, namespace}, query ->
        from(t in query,
          where: t.namespace == ^namespace
        )
    end
  end

  mutation :create, Template
  mutation :update, Template
  mutation :delete, Template
  mutation :duplicate, {Template, change_fields: [:name]}

  def get_var_by_type(var_type), do: Keyword.get(Var.types(), var_type)

  def render_var(%{type: "string", value: value}), do: value
  def render_var(%{type: "text", value: value}), do: value
  def render_var(%{type: "boolean", value: value}), do: value || false
  def render_var(%{type: "html", value: value}), do: value
  def render_var(%{type: "color", value: value}), do: value

  @doc """
  Trims encoded module string, base decodes and converts to terms
  """
  def deserialize_modules(encoded_modules) do
    encoded_modules
    |> String.trim()
    |> Base.decode64!()
    |> Brando.Utils.binary_to_term()
  end

  @doc """
  Maps all ids to nil, converts terms to binary and base encodes
  """
  def serialize_modules(modules) do
    modules
    |> Enum.map(&Map.put(&1, :id, nil))
    |> Brando.Utils.term_to_binary()
    |> Base.encode64()
  end
end
