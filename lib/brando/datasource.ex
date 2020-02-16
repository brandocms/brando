defmodule Brando.Datasource do
  import Ecto.Query

  @doc """
  List all registered data sources
  """
  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :datasources, accumulate: true)
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    datasources = Module.get_attribute(env.module, :datasources)
    compile(datasources)
  end

  @doc false
  def compile(datasources) do
    prelude = for {type, datasource} <- datasources,
        {key, val} <- datasource do
      quote do
        def __datasource__(unquote(type), unquote(key)) do
          unquote(Macro.escape(val))
        end
      end
    end
    postlude = quote do
      def __datasources__ do
        unquote(Macro.escape(datasources))
      end
    end

    [prelude, postlude]
  end

  defmacro datasource(type, map) do
    quote do
      Module.put_attribute(__MODULE__, :datasources, {unquote(type), unquote(map)})
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
    keys =
      mod.__datasources__()
      |> Enum.map(fn {k, v} -> {k, Map.keys(v)} end)
      |> Enum.into(%{})
    {:ok, keys}
  end

  @doc """
  Grab entry from database
  """
  def get_many(module, query) do
    mod = Module.concat([module])
    mod.__datasource__(:many, String.to_existing_atom(query)).()
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
