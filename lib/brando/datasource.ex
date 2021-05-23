defmodule Brando.Datasource do
  @moduledoc """
  Helpers to register datasources for interfacing with the block editor

  ### many

  A set of entries is returned automatically

  ### Selection

  User can pick entries manually.

  Requires both a `list` function and a `get` function. The `list` function must return a list of maps in
  the shape of `[%{id: 1, label: "Label"}]`.

  The get function queries by a supplied list of `ids`:

  ```
  fn _module, ids ->
    results =
      from t in Post,
        where: t.id in ^ids,
        order_by: fragment("array_position(?, ?)", ^ids, t.id)

    {:ok, Repo.all(results)}
  ```

  The `order_by: fragment(...)` sorts the returned results in the same order as the supplied `ids`

  ## Example

  In your schema:

      use Brando.Datasource

      datasources do
        list :all_posts_from_year, fn module, arg ->
          {:ok, Repo.all(from t in module, where: t.year == ^arg)}
        end

        list :all_posts, fn _, _ -> Posts.list_posts() end

        selection
          :featured,
            fn _, _ ->
              {:ok, posts} = Posts.list_posts()
              {:ok, Enum.map(posts, &(%{id: &1.id, label: &1.title}))}
            end,
            fn _, ids ->
              results =
                from t in Post,
                  where: t.id in ^ids,
                  order_by: fragment("array_position(?, ?)", ^ids, t.id)

              {:ok, Repo.all(results)}
            end
      end

  These data source points are now available through the block editor when you create a Datasource block.

  ## Common issues

  If your datasource fetches related items, pages using your datasource might not be updated
  when these related items are created, updated or deleted.

  For instance:

  We have a schema `Area` that has many `Grantee`s.

  The `Area` has this datasource:

      list :all_areas_with_grants, fn _, _ ->
        grantee_query = from(t in Areas.Grantee, where: t.status == :published, order_by: t.name)
        opts = %{order: [{:asc, :name}], status: :published, preload: [{:grantees, grantee_query}]}
        Areas.list_areas(opts)
      end

  On a page we have a `DatasourceBlock` that grabs `:all_areas_with_grants`. When deleting or
  updating a grant, this Datasource will not be updated since the datasource is listening for
  `Area` changes, which are not triggered.

  To solve, we can add it as a callback to each mutation for `Grantee`:

      mutation :create, Grantee do
        fn entry ->
          # update datasource that references :all_areas_with_grants
          Brando.Datasource.update_datasource({Area, :list, :all_areas_with_grants}, entry)
        end
      end

      mutation :update, Grantee do
        fn entry ->
          # update datasource that references :all_areas_with_grants
          Brando.Datasource.update_datasource({Area, :list, :all_areas_with_grants}, entry)
        end
      end

      mutation :delete, Grantee do
        fn entry ->
          # update datasource that references :all_areas_with_grants
          Brando.Datasource.update_datasource({Area, :list, :all_areas_with_grants}, entry)
        end
      end

  OR if you know that all changes to the `:all_areas_with_grants` are coming from `Grantee`
  mutations, you can move the datasource to the `Grantee` schema instead!

  """
  alias Brando.Villain
  import Ecto.Query

  @doc """
  List all registered data sources
  """
  defmacro __using__(_) do
    quote do
      import Ecto.Query
      import unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :datasources_list, accumulate: true)
      Module.register_attribute(__MODULE__, :datasources_single, accumulate: true)
      Module.register_attribute(__MODULE__, :datasources_selection, accumulate: true)
      @before_compile unquote(__MODULE__)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    datasources_list = Module.get_attribute(env.module, :datasources_list)
    datasources_single = Module.get_attribute(env.module, :datasources_single)
    datasources_selection = Module.get_attribute(env.module, :datasources_selection)

    [
      compile(:list, datasources_list),
      compile(:single, datasources_single),
      compile(:selection, datasources_selection)
    ]
  end

  @doc false
  def compile(:list, datasources_list) do
    quote do
      def __datasources__(:list) do
        unquote(datasources_list)
      end
    end
  end

  @doc false
  def compile(:single, datasources_single) do
    quote do
      def __datasources__(:single) do
        unquote(datasources_single)
      end
    end
  end

  @doc false
  def compile(:selection, datasources_selection) do
    quote do
      def __datasources__(:selection) do
        unquote(datasources_selection)
      end
    end
  end

  defmacro datasources(do: block) do
    quote do
      unquote(block)
    end
  end

  defmacro list(key, fun) do
    quote do
      Module.put_attribute(__MODULE__, :datasources_list, unquote(key))

      def __datasource__(:list, unquote(key)) do
        case unquote(fun) do
          {:ok, []} -> {:error, :no_entries}
          result -> result
        end
      end
    end
  end

  @deprecated """
  Use Datasource.list/2 instead.
  """
  defmacro many(key, fun) do
    quote do
      Module.put_attribute(__MODULE__, :datasources_list, unquote(key))

      def __datasource__(:list, unquote(key)) do
        case unquote(fun) do
          {:ok, []} -> {:error, :no_entries}
          {:ok, nil} -> {:error, :no_entries}
          result -> result
        end
      end
    end
  end

  defmacro single(key, fun) do
    quote do
      Module.put_attribute(__MODULE__, :datasources_single, unquote(key))

      def __datasource__(:single, unquote(key)) do
        case unquote(fun) do
          {:ok, nil} -> {:error, :no_entries}
          result -> result
        end
      end
    end
  end

  defmacro selection(key, list_fun, get_fun) do
    quote do
      Module.put_attribute(__MODULE__, :datasources_selection, unquote(key))

      def __datasource__(:list_selection, unquote(key)) do
        unquote(list_fun)
      end

      def __datasource__(:get_selection, unquote(key)) do
        case unquote(get_fun) do
          {:ok, []} -> {:error, :no_entries}
          {:ok, nil} -> {:error, :no_entries}
          result -> result
        end
      end
    end
  end

  @doc """
  Show all available datasources
  """
  def list_datasources do
    {:ok, modules} = :application.get_key(Brando.otp_app(), :modules)
    {:ok, Enum.filter(modules, &is_datasource/1)}
  end

  @doc """
  List keys for module
  """
  def list_datasource_keys(module_binary) do
    module = Module.concat([module_binary])

    list_keys = module.__datasources__(:list)
    selection_keys = module.__datasources__(:selection)
    single_keys = []

    {:ok, %{list: list_keys, single: single_keys, selection: selection_keys}}
  end

  @doc """
  Grab list of entries from database
  """
  def get_list(module_binary, query, arg) do
    module = Module.concat([module_binary])
    module.__datasource__(:list, String.to_existing_atom(query)).(module_binary, arg)
  end

  @doc """
  List available entries in selection from database
  """
  def list_selection(module_binary, query, arg) do
    module = Module.concat([module_binary])
    module.__datasource__(:list_selection, String.to_existing_atom(query)).(module_binary, arg)
  end

  @doc """
  Get selection by [ids] from database
  """
  def get_selection(module_binary, query, ids) do
    module = Module.concat([module_binary])
    module.__datasource__(:get_selection, String.to_existing_atom(query)).(module_binary, ids)
  end

  @doc """
  Grab single entry from database
  """
  def get_single(module_binary, query, arg) do
    module = Module.concat([module_binary])
    module.__datasource__(:single, String.to_existing_atom(query)).(module_binary, arg)
  end

  @doc """
  Look through all villains for datasources using `schema`
  """
  def update_datasource(datasource_module, entry \\ nil) do
    if is_datasource(datasource_module) do
      villains = Villain.list_villains()

      for {schema, fields} <- villains do
        Enum.map(fields, &parse_fields(datasource_module, &1, schema))
      end
    end

    {:ok, entry}
  end

  defp parse_fields(datasource_module, {:villain, data_field, html_field}, schema) do
    process_field(schema, datasource_module, data_field, html_field)
  end

  defp parse_fields(datasource_module, field, schema) do
    process_field(
      schema,
      datasource_module,
      field.name,
      Villain.get_html_field(schema, field).name
    )
  end

  defp process_field(schema, datasource_module, data_field, html_field) do
    ids = list_ids_with_datasource(schema, datasource_module, data_field)

    unless Enum.empty?(ids) do
      Villain.rerender_html_from_ids({schema, data_field, html_field}, ids)
    end
  end

  @doc """
  List ids of `schema` records that has a datasource matching schema OR
  a module containing a datasource matching schema.
  """
  def list_ids_with_datasource(schema, datasource, data_field \\ :data)

  def list_ids_with_datasource(
        schema,
        {datasource_module, datasource_type, datasource_query},
        data_field
      ) do
    ds_block = %{
      type: "datasource",
      data: %{module: datasource_module, type: datasource_type, query: datasource_query}
    }

    t = [
      ds_block
    ]

    refed_t = [
      %{
        type: "module",
        data: %{refs: [%{data: ds_block}]}
      }
    ]

    contained_t = [
      %{
        type: "container",
        data: %{blocks: [ds_block]}
      }
    ]

    Brando.repo().all(
      from s in schema,
        select: s.id,
        where: fragment("?::jsonb @> ?::jsonb", field(s, ^data_field), ^t),
        or_where: fragment("?::jsonb @> ?::jsonb", field(s, ^data_field), ^contained_t),
        or_where: fragment("?::jsonb @> ?::jsonb", field(s, ^data_field), ^refed_t)
    )
  end

  def list_ids_with_datasource(schema, datasource_module, data_field) do
    ds_block = %{
      type: "datasource",
      data: %{module: datasource_module}
    }

    t = [
      ds_block
    ]

    refed_t = [
      %{
        type: "module",
        data: %{refs: [%{data: ds_block}]}
      }
    ]

    contained_t = [
      %{
        type: "container",
        data: %{blocks: [ds_block]}
      }
    ]

    Brando.repo().all(
      from s in schema,
        select: s.id,
        where: fragment("?::jsonb @> ?::jsonb", field(s, ^data_field), ^t),
        or_where: fragment("?::jsonb @> ?::jsonb", field(s, ^data_field), ^contained_t),
        or_where: fragment("?::jsonb @> ?::jsonb", field(s, ^data_field), ^refed_t)
    )
  end

  @doc """
  Check if `schema` is a datasource
  """
  def is_datasource({schema, _, _}) do
    {:__datasource__, 2} in schema.__info__(:functions)
  end

  def is_datasource(schema) do
    {:__datasource__, 2} in schema.__info__(:functions)
  end
end
