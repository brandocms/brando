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

  alias Brando.Content.Block
  alias Brando.Content.Module
  alias Brando.Content.Palette
  alias Brando.Content.TableTemplate
  alias Brando.Content.Template
  alias Brando.Villain

  query :list, Block, do: fn query -> from(q in query) end

  filters Block do
    fn
      {:name, name}, query ->
        from(q in query, where: ilike(q.name, ^"%#{name}%"))

      {:class, class}, query ->
        from(q in query, where: ilike(q.class, ^"%#{class}%"))

      {:module_id, module_id}, query ->
        from(q in query, where: q.module_id == ^module_id)

      {:ids, ids}, query ->
        from(q in query, where: q.id in ^ids)
    end
  end

  query(:list, Module, do: fn query -> from(q in query) end)

  filters Module do
    fn
      {:name, name}, query ->
        from(q in query, where: ilike(q.name, ^"%#{name}%"))

      {:class, class}, query ->
        from(q in query, where: ilike(q.class, ^"%#{class}%"))

      {:ids, ids}, query ->
        from(q in query, where: q.id in ^ids)

      {:parent_id, nil}, query ->
        from(q in query, where: is_nil(q.parent_id))

      {:parent_id, parent_id}, query ->
        from(q in query, where: q.parent_id == ^parent_id)

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
        from(q in query, where: q.datasource == ^datasource)

      {:datasource_module, datasource_module}, query ->
        from(q in query, where: q.datasource_module == ^datasource_module)

      {:datasource_type, datasource_type}, query ->
        from(q in query, where: q.datasource_type == ^datasource_type)

      {:datasource_query, datasource_query}, query ->
        from(q in query, where: q.datasource_query == ^datasource_query)
    end
  end

  query(:single, Module, do: fn query -> from(q in query) end)

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
      Villain.render_entries_with_module_id(entry.id)

      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        "brando:modules",
        {entry, [:module, :updated]}
      )

      {:ok, entry}
    end
  end

  mutation :delete, Module
  mutation :duplicate, {Module, change_fields: [:name, :class, vars: &duplicate_vars/2]}

  def duplicate_vars(entry, _) do
    preloaded_vars = Brando.repo().preload(entry, :vars)
    require Logger

    Logger.error("""

    duplicate_vars
    #{inspect(preloaded_vars, pretty: true)}

    """)

    []
  end

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

  query(:list, Palette, do: fn query -> from(q in query) end)

  filters Palette do
    fn
      {:name, name}, query ->
        from(q in query, where: ilike(q.name, ^"%#{name}%"))

      {:key, key}, query ->
        from(q in query, where: ilike(q.key, ^"%#{key}%"))

      {:color, color}, query ->
        from(q in query, where: jsonb_contains(q, :colors, [%{hex_value: color}]))

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

  query(:single, Palette, do: fn query -> from(q in query) end)

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
    fn palette ->
      Villain.render_entries_with_palette_id(palette.id)
      Brando.Cache.Palettes.set()

      {:ok, palette}
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

  @doc """
  Get color from palette by key

  ## Example

      iex> get_color(palette, "fg")
      "#ef00aa"

  """
  def get_color(%Palette{} = palette, color_key, fallback \\ "") do
    case Enum.find(palette.colors, &(&1.key == color_key)) do
      nil -> fallback
      color -> color.hex_value
    end
  end

  ## Templates
  ##

  query(:list, Template, do: fn query -> from(q in query) end)

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

  query(:single, Template, do: fn query -> from(q in query) end)

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
  ## Table Templates
  ##

  query(:list, TableTemplate, do: fn query -> from(q in query) end)

  filters TableTemplate do
    fn
      {:name, name}, query ->
        from(q in query, where: ilike(q.name, ^"%#{name}%"))
    end
  end

  query(:single, TableTemplate, do: fn query -> from(q in query) end)

  matches TableTemplate do
    fn
      {:id, id}, query ->
        from(t in query, where: t.id == ^id)

      {:name, name}, query ->
        from(t in query,
          where: t.name == ^name
        )
    end
  end

  mutation :create, TableTemplate
  mutation :update, TableTemplate
  mutation :delete, TableTemplate
  mutation :duplicate, {TableTemplate, change_fields: [:name]}

  def list_identifiers do
    query =
      from(t in Brando.Content.Identifier,
        order_by: [asc: t.schema, asc: t.entry_id]
      )

    {:ok, Brando.repo().all(query)}
  end

  def list_identifiers(schema, list_opts) when is_atom(schema) do
    initial_query =
      from(t in Brando.Content.Identifier,
        where: t.schema == ^schema
      )

    query =
      Brando.Query.run_list_query_reducer(
        Brando.Query,
        list_opts,
        initial_query,
        Brando.Content.Identifier
      )

    # query = (language && from(t in query, where: t.language == ^language)) || query

    query =
      from(t in query,
        order_by: [asc: t.schema, asc: t.language, asc: t.title]
      )

    {:ok, Brando.repo().all(query)}
  end

  def list_identifiers(schemas, list_opts) when is_list(schemas) do
    initial_query =
      from(t in Brando.Content.Identifier,
        where: t.schema in ^schemas
      )

    query =
      Brando.Query.run_list_query_reducer(
        Brando.Query,
        list_opts,
        initial_query,
        Brando.Content.Identifier
      )

    # query = (language && from(t in query, where: t.language == ^language)) || query

    query =
      from(t in query,
        order_by: [asc: t.schema, asc: t.language, asc: t.title]
      )

    {:ok, Brando.repo().all(query)}
  end

  def list_identifiers(ids) when is_list(ids) do
    query =
      from(t in Brando.Content.Identifier,
        where: t.id in ^ids,
        order_by: fragment("array_position(?, ?)", ^ids, t.id)
      )

    {:ok, Brando.repo().all(query)}
  end

  def list_identifiers_for(entries) when is_list(entries) do
    ids_and_schemas =
      entries
      |> Enum.with_index()
      |> Enum.map(&%{id: elem(&1, 0).id, schema: elem(&1, 0).__struct__, sequence: elem(&1, 1)})

    query =
      from(x in Brando.Content.Identifier,
        inner_join:
          j in fragment(
            "SELECT distinct * from jsonb_to_recordset(?) AS j(id int,schema text,sequence int)",
            ^ids_and_schemas
          ),
        on: x.entry_id == j.id and x.schema == j.schema,
        order_by: [asc: j.sequence]
      )

    identifiers = Brando.repo().all(query)
    {:ok, identifiers}
  end

  def get_entries_from_identifiers(identifiers, preloads \\ []) do
    entry_blueprint =
      identifiers
      |> Enum.with_index()
      |> Enum.map(&{elem(&1, 0).schema, elem(&1, 0).entry_id, elem(&1, 1)})

    grouped_entries = Enum.group_by(entry_blueprint, &elem(&1, 0))

    # build some queries
    unsorted_entries =
      for {schema, entry_blueprints} <- grouped_entries do
        schema_ids = Enum.map(entry_blueprints, &elem(&1, 1))

        query =
          from t in schema,
            where: t.id in ^schema_ids,
            order_by: fragment("array_position(?, ?)", ^schema_ids, t.id),
            preload: ^preloads

        Brando.repo().all(query)
      end

    flattened_unsorted_entries = List.flatten(unsorted_entries)

    sorted_entries =
      Enum.map(entry_blueprint, fn {schema, id, _} ->
        Enum.find(flattened_unsorted_entries, fn entry ->
          entry.id == id && schema == entry.__struct__
        end)
      end)

    {:ok, sorted_entries}
  end

  def has_identifier(module) do
    case module.__has_identifier__ do
      true -> {:ok, :has_identifier}
      false -> {:error, :no_identifier}
    end
  rescue
    UndefinedFunctionError -> {:error, :no_identifier}
  end

  def delete_identifier(module, entry) do
    with {:ok, :has_identifier} <- has_identifier(module),
         {:ok, identifier} <- get_identifier(module, entry) do
      Brando.repo().delete(identifier)
    else
      _ ->
        {:ok, false}
    end
  end

  def delete_identifier(identifier) do
    Brando.repo().delete(identifier)
  end

  def create_identifier(Brando.Images.Image, _entry), do: {:ok, false}

  def create_identifier(module, entry) do
    with {:ok, :has_identifier} <- has_identifier(module) do
      new_identifier = module.__identifier__(entry)
      changeset = Ecto.Changeset.change(new_identifier)

      Brando.repo().insert(changeset,
        on_conflict: {:replace_all_except, [:id]},
        conflict_target: [:entry_id, :schema],
        returning: true
      )
    else
      _ ->
        {:ok, false}
    end
  end

  def update_identifier(module, entry) do
    with {:ok, :has_identifier} <- has_identifier(module),
         {:ok, identifier} <- get_identifier(module, entry) do
      new_identifier = module.__identifier__(entry)
      language = new_identifier.language && to_string(new_identifier.language)

      updated_identifier_data = %{
        title: new_identifier.title,
        language: language,
        status: new_identifier.status,
        cover: new_identifier.cover,
        updated_at: new_identifier.updated_at,
        url: new_identifier.url
      }

      changeset = Ecto.Changeset.change(identifier, updated_identifier_data)
      Brando.repo().update(changeset)
    else
      {:error, {:identifier, :not_found}} ->
        create_identifier(module, entry)

      _err ->
        {:ok, false}
    end
  end

  def get_identifier(id) do
    query =
      from(t in Brando.Content.Identifier,
        where: t.id == ^id,
        limit: 1
      )

    case Brando.repo().one(query) do
      nil ->
        {:error, {:identifier, :not_found}}

      identifier ->
        {:ok, identifier}
    end
  end

  def get_identifier(module, entry) do
    query =
      from(t in Brando.Content.Identifier,
        where: t.schema == ^module and t.entry_id == ^entry.id,
        limit: 1
      )

    case Brando.repo().one(query) do
      nil ->
        {:error, {:identifier, :not_found}}

      identifier ->
        {:ok, identifier}
    end
  end

  def render_var(%{type: :string, value: value}), do: value
  def render_var(%{type: :text, value: value}), do: value
  def render_var(%{type: :boolean, value_boolean: value}), do: value || false
  def render_var(%{type: :html, value: value}), do: value
  def render_var(%{type: :color, value: value}), do: value
  def render_var(%{type: :select, value: value, default: default}), do: value || default

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
