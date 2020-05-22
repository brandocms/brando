defmodule Brando.Datasource do
  @moduledoc """
  Helpers to register datasources for interfacing with the block editor

  ## Example

  In your schema:

      use Brando.Datasource

      datasources do
        many :all_posts_from_year, fn module, arg ->
          {:ok, Repo.all(from t in module, where: t.year == ^arg)}
        end

        many :all_posts, fn _, _ -> Posts.list_posts() end
      end

  These two data source points are now available through the block editor when you create a Datasource block.

  """
  import Ecto.Query

  @doc """
  List all registered data sources
  """
  defmacro __using__(_) do
    quote do
      import Ecto.Query
      import unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :datasources_many, accumulate: true)
      Module.register_attribute(__MODULE__, :datasources_one, accumulate: true)
      @before_compile unquote(__MODULE__)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    datasources_many = Module.get_attribute(env.module, :datasources_many)
    datasources_one = Module.get_attribute(env.module, :datasources_one)
    [compile(:many, datasources_many), compile(:one, datasources_one)]
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

  @deprecated """
  Use new datasources syntax:

    datasources do
      many :all, fn module, _arg -> {:ok, Repo.all(from t in module, order_by: t.name)} end
      one :latest, fn _module, _arg -> get_latest_post() end
    end
  """
  defmacro datasource(_, _) do
    raise "Deprecated"
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
        unquote(fun)
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
    one_keys = []

    {:ok, %{many: many_keys, one: one_keys}}
  end

  @doc """
  Grab entry from database
  """
  def get_many(module, query, arg) do
    mod = Module.concat([module])
    mod.__datasource__(:many, String.to_existing_atom(query)).(module, arg)
  end

  @doc """
  Look through all villains for datasources using `schema`
  """
  def update_datasource(datasource, entry) do
    villains = Brando.Villain.list_villains()

    for {schema, fields} <- villains do
      Enum.reduce(fields, [], fn {_, data_field, html_field}, acc ->
        case list_ids_with_datasource(schema, datasource, data_field) do
          [] ->
            acc

          ids ->
            [Brando.Villain.rerender_html_from_ids({schema, data_field, html_field}, ids) | acc]
        end
      end)
    end

    {:ok, entry}
  end

  @doc """
  List ids of `schema` records that has a datasource matching schema
  """
  def list_ids_with_datasource(schema, datasource, data_field \\ :data) do
    # module = Module.concat([datasource])
    t = [%{type: "datasource", data: %{module: datasource}}]

    Brando.repo().all(
      from s in schema,
        select: s.id,
        where: fragment("?::jsonb @> ?::jsonb", field(s, ^data_field), ^t)
    )
  end
end
