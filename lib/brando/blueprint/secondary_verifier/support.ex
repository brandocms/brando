defmodule Brando.Blueprint.SecondaryVerifier.Support do
  @moduledoc false

  alias Spark.Dsl.Entity
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @doc "Validates atom keys shared by secondary Blueprint entities."
  def verify_key(_dsl_state, _path, _entity, _label, key)
      when is_atom(key) and key not in [nil, false, true],
      do: :ok

  def verify_key(dsl_state, path, entity, label, key) do
    error(dsl_state, path, entity, "#{label} key must be a meaningful atom, got: #{inspect(key)}")
  end

  @doc "Validates required display strings shared by secondary Blueprint entities."
  def verify_non_empty_string(dsl_state, path, entity, label, value) do
    if non_empty_string?(value) do
      :ok
    else
      error(dsl_state, path, entity, "#{label} must be a non-empty string")
    end
  end

  @doc "Returns whether a value is a non-empty string."
  def non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""

  @doc "Returns whether a module is available and defines a struct."
  def struct_module?(module) do
    available_module?(module) and function_exported?(module, :__struct__, 0)
  end

  @doc "Returns whether a module is available and exports the requested callback."
  def callback_module?(module, function, arity) do
    available_module?(module) and function_exported?(module, function, arity)
  end

  @doc "Validates entities in declaration order and returns the first error."
  def validate_entities(entities, validator) do
    Enum.reduce_while(entities, :ok, fn entity, :ok ->
      case validator.(entity) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc "Returns the second entity carrying a duplicate derived key, if any."
  def find_duplicate(entities, key_fun) do
    entities
    |> Enum.reduce_while(MapSet.new(), fn entity, seen ->
      key = key_fun.(entity)

      if MapSet.member?(seen, key) do
        {:halt, {:duplicate, entity}}
      else
        {:cont, MapSet.put(seen, key)}
      end
    end)
    |> case do
      {:duplicate, entity} -> entity
      %MapSet{} -> nil
    end
  end

  @doc "Builds a source-annotated Spark DSL error for a secondary Blueprint entity."
  def error(dsl_state, path, entity, message) do
    {:error,
     DslError.exception(
       module: Verifier.get_persisted(dsl_state, :module),
       path: path,
       location: Entity.anno(entity),
       message: message
     )}
  end

  defp available_module?(module) when is_atom(module) and module not in [nil, false, true] do
    match?({:module, ^module}, Code.ensure_compiled(module))
  end

  defp available_module?(_module), do: false
end
