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
  alias Brando.Content.Var
  alias Brando.Villain

  @default_vars %{
    boolean: Var.Boolean,
    string: Var.String,
    text: Var.Text,
    color: Var.Color,
    html: Var.Html,
    datetime: Var.Datetime
  }

  query :list, Module, do: fn query -> from(q in query, where: is_nil(q.deleted_at)) end

  filters Module do
    fn
      {:name, name}, query ->
        from(q in query, where: ilike(q.name, ^"%#{name}%"))

      {:class, class}, query ->
        from(q in query, where: ilike(q.class, ^"%#{class}%"))

      {:namespace, namespace}, query ->
        query =
          from(t in query,
            where: is_nil(t.deleted_at),
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

  query :single, Module, do: fn query -> from(q in query, where: is_nil(q.deleted_at)) end

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

  mutation :create, Module

  mutation :update, Module do
    fn entry ->
      Villain.update_module_in_fields(entry.id)

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

  query :list, Palette, do: fn query -> from(q in query, where: is_nil(q.deleted_at)) end

  filters Palette do
    fn
      {:name, name}, query ->
        from(q in query, where: ilike(q.name, ^"%#{name}%"))

      {:key, key}, query ->
        from(q in query, where: ilike(q.key, ^"%#{key}%"))

      {:color, color}, query ->
        from q in query,
          where: fragment("?::jsonb @> ?::jsonb", field(q, :colors), ^[%{hex_value: color}])

      {:namespace, namespace}, query ->
        query =
          from(t in query,
            where: is_nil(t.deleted_at),
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

  query :single, Palette, do: fn query -> from(q in query, where: is_nil(q.deleted_at)) end

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

  def get_var_by_type(var_type) do
    Map.get(@default_vars, var_type)
  end
end
