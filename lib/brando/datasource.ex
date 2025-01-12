defmodule Brando.Datasource do
  @moduledoc """
  Helpers to register datasources for interfacing with the block editor

      datasources do
        datasource :all_posts_from_year do
          type :list
          list fn module, _language, %{"year" => year} ->
            {:ok, Repo.all(from t in module, where: t.year == ^year)}
          end
        end

        datasource :featured_entries do
          type :selection
          list fn _module, language, _vars ->
            Brando.Content.list_identifiers(
              [MyApp.Projects.Project, MyApp.Articles.Article],
              %{language: language, order: "asc schema, asc language, asc entry_id"})
          end

          get fn identifiers ->
            Brando.Content.get_entries_from_identifiers(
              identifiers,
              %{preload: [:categories, :cover, :palette]}
            )
          end
        end
      end

  ### List

  A set of entries is returned automatically

  #### Example

        datasource :all_posts_from_year do
          type :list
          list fn module, _language, %{"year" => year} ->
            {:ok, Repo.all(from t in module, where: t.year == ^year)}
          end
        end

        datasource :all_posts do
          type :list
          list fn _module, _language, _vars -> Posts.list_posts() end
        end

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
    end
    ```

    You can also supply multiple modules:

    ```
    fn _module, language, _vars ->
      Brando.Content.list_identifiers(
        [MyApp.Projects.Project, MyApp.Articles.Article],
        %{language: language, order: "asc schema, asc language, asc entry_id"})
    end
    ```


  - The get function receives selected identifiers as an argument and must return
    the ordered selected entries

    ```
    fn identifiers ->
      Brando.Content.get_entries_from_identifiers(
        identifiers,
        %{preload: [:categories, :cover, :palette]}
      )
    end
  end
    ```

  ## Example

  In your schema:

      datasources do
        datasource :all_posts_from_year do
          type :list
          list fn module, _language, %{"year" => year} ->
            {:ok, Repo.all(from t in module, where: t.year == ^year)}
          end
        end

        datasource :featured_entries do
          type :selection
          list fn _module, language, _vars ->
            Brando.Content.list_identifiers(
              [MyApp.Projects.Project, MyApp.Articles.Article],
              %{language: language, order: "asc schema, asc language, asc entry_id"})
          end

          get fn identifiers ->
            Brando.Content.get_entries_from_identifiers(
              identifiers,
              %{preload: [:categories, :cover, :palette]}
            )
          end
        end
      end

  These data source points are now available through the block editor when you create a Datasource block.

  ## Common issues

  If your datasource fetches related items, pages using your datasource might not be updated
  when these related items are created, updated or deleted.

  For instance:

  We have a schema `Area` that has many `Grantee`s.

  The `Area` has this datasource:

      datasource :all_areas_with_grants do
        type :list
        list fn _module, _language, _vars ->
          grantee_query = from(t in Areas.Grantee, where: t.status == :published, order_by: t.name)
          opts = %{order: [{:asc, :name}], status: :published, preload: [{:grantees, grantee_query}]}
          Areas.list_areas(opts)
        end
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
  @deprecated "Datasources are imported through the blueprint now. Remove `use Brando.Datasource`"
  defmacro __using__(_) do
    quote do
      import Brando.Datasource, only: [list: 2, get: 1, selection: 3]
    end
  end

  def datasources(module) do
    Spark.Dsl.Extension.get_entities(module, [:datasources])
  end

  def datasources(module, type) do
    module
    |> Spark.Dsl.Extension.get_entities([:datasources])
    |> Enum.filter(&(&1.type == type))
    |> Enum.map(& &1.key)
  end

  def get_datasource(module, :*, key) do
    module
    |> Spark.Dsl.Extension.get_entities([:datasources])
    |> Enum.find(&(&1.key == key))
  end

  def get_datasource(module, type, key) do
    module
    |> Spark.Dsl.Extension.get_entities([:datasources])
    |> Enum.find(&(&1.type == type && &1.key == key))
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

    all_datasources = datasources(module)

    splits =
      Enum.reduce(all_datasources, %{}, fn ds, acc ->
        Map.update(acc, ds.type, [ds.key], &[ds.key | &1])
      end)

    {:ok, splits}
  end

  @doc """
  Grab list of entries from database
  """
  def list_results(module_binary, key, vars, language) do
    atom_key = (is_binary(key) && String.to_atom(key)) || key
    module = Module.concat([module_binary])
    ds = get_datasource(module, :*, atom_key)
    ds.list.(module_binary, language, vars)
  end

  @doc """
  Get selection by [ids] from database
  """
  def get_selection(_module_binary, _key, []), do: {:ok, []}
  def get_selection(_module_binary, _key, nil), do: {:ok, []}

  def get_selection(module_binary, key, ids) do
    atom_key = (is_binary(key) && String.to_atom(key)) || key
    module = Module.concat([module_binary])
    ds = get_datasource(module, :selection, atom_key)
    {:ok, identifiers} = Brando.Content.list_identifiers(ids)
    ds.get.(identifiers)
  end

  @doc """
  Grab single entry from database
  """
  def get_single(module_binary, key, identifier) do
    atom_key = (is_binary(key) && String.to_atom(key)) || key
    module = Module.concat([module_binary])
    ds = get_datasource(module, :single, atom_key)
    ds.get.(identifier)
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
  def is_datasource({schema, _, _}), do: {:__datasource__, 0} in schema.__info__(:functions)
  def is_datasource(schema), do: {:__datasource__, 0} in schema.__info__(:functions)

  def get_meta(module, type, query) do
    module
    |> List.wrap()
    |> Module.concat()
    |> Spark.Dsl.Extension.get_entities([:datasources])
    |> Enum.find(&(&1.type == type && &1.key == String.to_existing_atom(query)))
    |> case do
      nil -> nil
      datasource -> datasource.meta
    end
  end

  ## DEPRECATED——REMOVE in 0.55

  @deprecated "list/2 outside of datasource/1 is deprecated. Wrap inside datasource/1"
  defmacro list(_, {_, _, [{_, _, [[_, _], _]}]}, _) do
    raise "datasource :list callbacks with 2 arity is deprecated. use `fn module, language, vars -> ... end` instead"
  end

  @deprecated "list/2 outside of datasource/1 is deprecated. Wrap inside datasource/1"
  defmacro list(_key, _fun) do
    nil
  end

  @deprecated "single/2 outside of datasource/1 is deprecated. Wrap inside datasource/1"
  defmacro single(_key, _fun) do
    nil
  end

  defmacro selection(_, {_, _, [{_, _, [[_, _], _]}]}, _) do
    raise "datasource :selection LIST callbacks with 2 arity is deprecated. use `fn module, language, vars -> ... end` instead"
  end

  defmacro selection(_, _, {_, _, [{_, _, [[_, _], _]}]}) do
    raise "datasource :selection GET callbacks with 2 arity (module, ids) is deprecated. use `fn identifiers -> ... end` instead"
  end

  @deprecated "selection/3 outside of datasource/1 is deprecated. Wrap inside datasource/1"
  defmacro selection(_key, _list_fun, _get_fun) do
    nil
  end
end
