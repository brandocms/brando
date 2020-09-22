defmodule Brando.Datasource do
  @moduledoc """
  Helpers to register datasources for interfacing with the block editor

  ### many

  A set of entries is returned automatically

  ### Selection

  User can pick entries manually.

  Required both a `list` function and a `get` function. The `list` function must return a list of maps in
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
        many :all_posts_from_year, fn module, arg ->
          {:ok, Repo.all(from t in module, where: t.year == ^arg)}
        end

        many :all_posts, fn _, _ -> Posts.list_posts() end

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

  """
  import Ecto.Query
  alias Brando.Villain

  @doc """
  List all registered data sources
  """
  defmacro __using__(_) do
    quote do
      import Ecto.Query
      import unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :datasources_many, accumulate: true)
      Module.register_attribute(__MODULE__, :datasources_one, accumulate: true)
      Module.register_attribute(__MODULE__, :datasources_selection, accumulate: true)
      @before_compile unquote(__MODULE__)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    datasources_many = Module.get_attribute(env.module, :datasources_many)
    datasources_one = Module.get_attribute(env.module, :datasources_one)
    datasources_selection = Module.get_attribute(env.module, :datasources_selection)

    [
      compile(:many, datasources_many),
      compile(:one, datasources_one),
      compile(:selection, datasources_selection)
    ]
  end

  @doc false
  def compile(:many, datasources_many) do
    quote do
      def __datasources__(:many) do
        unquote(datasources_many)
      end
    end
  end

  @doc false
  def compile(:one, datasources_one) do
    quote do
      def __datasources__(:one) do
        unquote(datasources_one)
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

  defmacro many(key, fun) do
    quote do
      Module.put_attribute(__MODULE__, :datasources_many, unquote(key))

      def __datasource__(:many, unquote(key)) do
        case unquote(fun) do
          {:ok, []} -> {:error, :no_entries}
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

    available_modules = Enum.filter(modules, &({:__datasource__, 2} in &1.__info__(:functions)))
    {:ok, available_modules}
  end

  @doc """
  List keys for module
  """
  def list_datasource_keys(module) do
    mod = Module.concat([module])

    many_keys = mod.__datasources__(:many)
    selection_keys = mod.__datasources__(:selection)
    one_keys = []

    {:ok, %{many: many_keys, one: one_keys, selection: selection_keys}}
  end

  @doc """
  Grab entry from database
  """
  def get_many(module, query, arg) do
    mod = Module.concat([module])
    mod.__datasource__(:many, String.to_existing_atom(query)).(module, arg)
  end

  @doc """
  List available entries in selection from database
  """
  def list_selection(module, query, arg) do
    mod = Module.concat([module])
    mod.__datasource__(:list_selection, String.to_existing_atom(query)).(module, arg)
  end

  @doc """
  Get selection by [ids] from database
  """
  def get_selection(module, query, ids) do
    mod = Module.concat([module])
    mod.__datasource__(:get_selection, String.to_existing_atom(query)).(module, ids)
  end

  @doc """
  Look through all villains for datasources using `schema`
  """
  def update_datasource(datasource, entry \\ nil) do
    villains = Villain.list_villains()

    for {schema, fields} <- villains,
        {_, data_field, html_field} <- fields do
      ids = list_ids_with_datasource(schema, datasource, data_field)

      unless Enum.empty?(ids) do
        Villain.rerender_html_from_ids(
          {schema, data_field, html_field},
          ids
        )
      end
    end

    {:ok, entry}
  end

  @doc """
  List ids of `schema` records that has a datasource matching schema
  """
  def list_ids_with_datasource(schema, datasource, data_field \\ :data) do
    t = [%{type: "datasource", data: %{module: datasource}}]

    Brando.repo().all(
      from s in schema,
        select: s.id,
        where: fragment("?::jsonb @> ?::jsonb", field(s, ^data_field), ^t)
    )
  end
end
