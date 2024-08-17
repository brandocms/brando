defmodule Brando.Datasource do
  @moduledoc """
  Helpers to register datasources for interfacing with the block editor

  ### List

  A set of entries is returned automatically

  #### Example

        list :all_posts_from_year, fn module, _language, %{"year" => year} ->
          {:ok, Repo.all(from t in module, where: t.year == ^year)}
        end

        list :all_posts, fn _module, _language, _vars -> Posts.list_posts() end

  The callback receives 3 arguments:

    - `module`
      The module the datasource is connected to

      - `language`
      The language the datasource was requested in

      - `vars`
      A map of variables passed on from the datasourced module. If the entry is
      rendered with `<.render_data conn={@conn} entry={@entry} />` you can also
      access the request in this map.

          Map.get(vars, "request")

      Within the request map there is a map of params you can use for matching
      categories or other URL data. An example var map:

          %{
            "category" => "animation",
            "request" => %{
              params: %{
                "category_slug" => "animation"
              },
              url: "/en/projects/animation"
            }
          }


  ### Selection

  User can pick entries manually.

  Requires both a `list` function and a `get` function.

  - The `list` function receives the module, language and datasource arguments and
    must return a list of identifiers (`Brando.Content.Identifier`)

    ```
    fn module, language, _vars ->
      Brando.Content.list_identifiers(module, %{language: language, order: "asc language, asc entry_id"})
    end,
    ```

    You can also supply multiple modules:

    ```
    fn _module, language, _vars ->
      Brando.Content.list_identifiers(
        [MyApp.Projects.Project, MyApp.Articles.Article],
        %{language: language, order: "asc schema, asc language, asc entry_id"})
    end,
    ```


  - The get function receives selected identifiers as an argument and must return
    the ordered selected entries

    ```
    fn identifiers ->
      Brando.Content.get_entries_from_identifiers(
        identifiers,
        [:categories, :cover, :palette]
      )
    end
  end
    ```

  ## Example

  In your schema:

      use Brando.Datasource

      datasources do
        list :all_posts_from_year, fn module, _language, %{"year" => year} ->
          {:ok, Repo.all(from t in module, where: t.year == ^year)}
        end

        list :all_posts, fn _, _, _ -> Posts.list_posts() end

        selection
          :featured,
            fn schema, language, _vars ->
              Brando.Content.list_identifiers(schema, %{language: language})
            end,
            fn identifiers ->
              entry_ids = Enum.map(identifiers, &(&1.entry_id))
              results =
                from t in Post,
                  where: t.id in ^entry_ids,
                  order_by: fragment("array_position(?, ?)", ^entry_ids, t.id)

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

      list :all_areas_with_grants, fn _module, _language, _vars ->
        grantee_query = from(t in Areas.Grantee, where: t.status == :published, order_by: t.name)
        opts = %{order: [{:asc, :name}], status: :published, preload: [{:grantees, grantee_query}]}
        Areas.list_areas(opts)
      end

  On a page we have a `ModuleBlock` with a datasource that grabs `:all_areas_with_grants`.
  When deleting or updating a grant, this module will not be updated since the datasource
  is listening for `Area` changes, which are not triggered.

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

  defmacro list(_, {_, _, [{_, _, [[_, _], _]}]}, _) do
    raise "datasource :list callbacks with 2 arity is deprecated. use `fn module, language, vars -> ... end` instead"
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

  defmacro selection(_, {_, _, [{_, _, [[_, _], _]}]}, _) do
    raise "datasource :selection LIST callbacks with 2 arity is deprecated. use `fn module, language, vars -> ... end` instead"
  end

  defmacro selection(_, _, {_, _, [{_, _, [[_, _], _]}]}) do
    raise "datasource :selection GET callbacks with 2 arity (module, ids) is deprecated. use `fn identifiers -> ... end` instead"
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

    {:ok,
     modules
     |> Enum.filter(&is_datasource/1)
     |> Enum.map(&to_string/1)}
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
  def get_list(module_binary, query, vars, language) do
    module = Module.concat([module_binary])
    module.__datasource__(:list, String.to_atom(query)).(module_binary, language, vars)
  end

  @doc """
  List available entries in selection from database
  """
  def list_selection(module_binary, query, language, vars) do
    module = Module.concat([module_binary])

    module.__datasource__(:list_selection, String.to_atom(query)).(
      module_binary,
      language,
      vars
    )
  end

  @doc """
  Get selection by [ids] from database
  """
  def get_selection(_module_binary, _query, []), do: {:ok, []}
  def get_selection(_module_binary, _query, nil), do: {:ok, []}

  def get_selection(module_binary, query, ids) do
    module = Module.concat([module_binary])
    {:ok, identifiers} = Brando.Content.list_identifiers(ids)
    module.__datasource__(:get_selection, String.to_atom(query)).(identifiers)
  end

  @doc """
  Grab single entry from database
  """
  def get_single(module_binary, query, arg) do
    module = Module.concat([module_binary])
    module.__datasource__(:single, String.to_atom(query)).(module_binary, arg)
  end

  @doc """
  Look through all villains for datasources using `schema`
  """
  def update_datasource(datasource_module, entry \\ nil) do
    if is_datasource(datasource_module) do
      datasource_module
      |> Villain.list_block_ids_using_datamodule()
      |> Villain.reject_blocks_belonging_to_entry(entry)
      |> Villain.enqueue_entry_map_for_render()
    end

    {:ok, entry}
  end

  @doc """
  Check if `schema` is a datasource
  """
  def is_datasource({schema, _, _}), do: {:__datasource__, 2} in schema.__info__(:functions)
  def is_datasource(schema), do: {:__datasource__, 2} in schema.__info__(:functions)
end
