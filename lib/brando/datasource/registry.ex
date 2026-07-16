defmodule Brando.Datasource.Registry do
  @moduledoc """
  Provides read-only access to datasource metadata registered by Blueprints.

  This boundary keeps metadata discovery independent of datasource invalidation
  and the content rendering pipeline.
  """

  alias Brando.RuntimeConfig
  alias Spark.Dsl.Extension

  @doc """
  Returns all datasources registered by `module`.
  """
  @spec all(module()) :: [struct()]
  def all(module), do: Extension.get_entities(module, [:datasources])

  @doc """
  Returns the keys for datasources of `type` registered by `module`.
  """
  @spec keys(module(), atom()) :: [atom()]
  def keys(module, type) do
    module
    |> all()
    |> Enum.filter(&(&1.type == type))
    |> Enum.map(& &1.key)
  end

  @doc """
  Finds a datasource by key, optionally restricting it to `type`.
  """
  @spec get(module(), atom(), atom()) :: struct() | nil
  def get(module, :*, key) do
    module
    |> all()
    |> Enum.find(&(&1.key == key))
  end

  def get(module, type, key) do
    module
    |> all()
    |> Enum.find(&(&1.type == type && &1.key == key))
  end

  @doc """
  Lists loaded application modules that register datasources.
  """
  @spec list_modules() :: {:ok, [String.t()]}
  def list_modules do
    {:ok, modules} = :application.get_key(RuntimeConfig.get(:otp_app), :modules)

    {:ok,
     modules
     |> Enum.filter(&datasource?/1)
     |> Enum.map(&to_string/1)}
  end

  @doc """
  Groups a module's datasource keys by datasource type.
  """
  @spec grouped_keys(module() | String.t()) :: {:ok, %{optional(atom()) => [atom()]}}
  def grouped_keys(module_name) do
    {module, _key} = resolve(module_name, :unused)

    grouped_keys =
      Enum.reduce(all(module), %{}, fn datasource, grouped ->
        Map.update(grouped, datasource.type, [datasource.key], &[datasource.key | &1])
      end)

    {:ok, grouped_keys}
  end

  @doc """
  Returns whether a schema declares one or more Blueprint datasources.
  """
  @spec datasource?(module() | {module(), atom(), atom()}) :: boolean()
  def datasource?({schema, _, _}), do: datasource?(schema)
  def datasource?(schema), do: {:__datasource__, 0} in schema.__info__(:functions)

  @doc """
  Returns datasource editor metadata for `type` and `query`.
  """
  @spec meta(module() | String.t(), atom(), atom() | String.t()) :: [struct()] | nil
  def meta(module_name, type, query) do
    {module, key} = resolve(module_name, query)

    case get(module, type, key) do
      nil -> nil
      datasource -> datasource.meta
    end
  end

  @doc false
  @spec resolve(module() | String.t() | [module() | String.t()], atom() | String.t()) :: {module(), atom()}
  def resolve(module_name, key) do
    module = Module.concat(List.wrap(module_name))
    Code.ensure_loaded(module)
    atom_key = if is_atom(key), do: key, else: String.to_existing_atom(key)
    {module, atom_key}
  end
end
