defmodule Brando.JSONLD.Schema do
  @deprecated "Move to blueprints"
  #! TODO: Delete when moving to Blueprints
  @moduledoc """
  Schema definitions for JSONLD schemas
  """

  @doc false
  defmacro __using__(_) do
    quote do
      import Brando.JSONLD.Schema, only: [json_ld_schema: 2]
      Module.register_attribute(__MODULE__, :json_ld_fields, accumulate: true)
      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(env) do
    json_ld_fields = Module.get_attribute(env.module, :json_ld_fields)
    json_ld_schema = Module.get_attribute(env.module, :json_ld_schema)

    quote do
      def extract_json_ld(data, extra_fields \\ []) do
        fields = unquote(json_ld_fields) ++ extra_fields

        Enum.reduce(fields, struct(unquote(json_ld_schema)), fn
          {name, {:references, target}}, acc ->
            result = %{"@id": "#{Brando.Utils.hostname()}/##{target}"}
            Map.put(acc, name, result)

          {name, value}, acc
          when is_integer(value) or is_binary(value) ->
            Map.put(acc, name, value)

          {name, {:string, path}}, acc
          when is_list(path) ->
            result = get_in(data, Enum.map(path, &Access.key/1))
            Map.put(acc, name, result)

          {name, {{:string, path}, {:mutator, mutation_function}}}, acc
          when is_list(path) ->
            value = get_in(data, Enum.map(path, &Access.key/1))
            result = mutation_function.(value)
            Map.put(acc, name, result)

          {name, {:string, mutation_function}}, acc
          when is_function(mutation_function) ->
            result = mutation_function.(data)
            Map.put(acc, name, result)

          {name, {schema, path}}, acc
          when is_list(path) ->
            value = get_in(data, Enum.map(path, &Access.key/1))
            result = schema.build(value)
            Map.put(acc, name, result)

          {name, {schema, populator_function}}, acc
          when is_function(populator_function) ->
            pf_result = populator_function.(data)
            result = schema.build(pf_result)
            Map.put(acc, name, result)

          {name, {{schema, path}, mutation_function}}, acc
          when not is_binary(schema) and
                 is_list(path) and
                 is_function(mutation_function) ->
            value = get_in(data, Enum.map(path, &Access.key/1))
            mf_result = mutation_function.(value)
            result = schema.build(mf_result)
            Map.put(acc, name, result)
        end)
      end
    end
  end

  # coveralls-ignore-start
  defmacro json_ld_schema(schema_module, do: block) do
    do_json_ld_schema(schema_module, block)
  end

  # coveralls-ignore-stop

  defp do_json_ld_schema(schema_module, block) do
    quote do
      Module.put_attribute(__MODULE__, :json_ld_schema, unquote(schema_module))

      try do
        import Brando.JSONLD.Schema
        unquote(block)
      after
        :ok
      end
    end
  end

  @doc """
  Defines a JSON LD field.

  This macro defines

    * a field name
    * a path to extract the data from
    * a mutator/generator function
  """
  defmacro field(name, {:references, target}) do
    quote do
      Module.put_attribute(
        __MODULE__,
        :json_ld_fields,
        {unquote(name), {:references, unquote(target)}}
      )
    end
  end

  # populate a field with a path without mutator function
  defmacro field(name, :string, path) when is_list(path) do
    quote do
      Module.put_attribute(
        __MODULE__,
        :json_ld_fields,
        {unquote(name), {:string, unquote(path)}}
      )
    end
  end

  # populate a field with a path with mutator function
  defmacro field(name, :string, path, mutation_function) when is_list(path) do
    quote do
      Module.put_attribute(
        __MODULE__,
        :json_ld_fields,
        {unquote(name), {{:string, unquote(path)}, {:mutator, unquote(mutation_function)}}}
      )
    end
  end

  # populate a field without a path with mutator function
  defmacro field(name, :string, mutation_function) when is_function(mutation_function) do
    quote do
      Module.put_attribute(
        __MODULE__,
        :json_ld_fields,
        {unquote(name), {:string, unquote(mutation_function)}}
      )
    end
  end

  # populate a field as a schema with populator function
  defmacro field(name, schema, nil) do
    raise "=> JSONLD/Schema >> Populating a field as schema requires a populator function - #{
            name
          } - #{inspect(schema)}"
  end

  defmacro field(name, schema, _) when is_binary(schema) do
    raise "=> JSONLD/Schema >> Populating a field as schema requires a schema as second arg - #{
            name
          } - #{inspect(schema)}"
  end

  defmacro field(name, schema, path) when is_list(path) do
    quote do
      Module.put_attribute(
        __MODULE__,
        :json_ld_fields,
        {unquote(name), {unquote(schema), unquote(path)}}
      )
    end
  end

  defmacro field(name, schema, populator_function) do
    quote do
      Module.put_attribute(
        __MODULE__,
        :json_ld_fields,
        {unquote(name), {unquote(schema), unquote(populator_function)}}
      )
    end
  end

  # populate a field as a schema with a path and populator function
  defmacro field(name, schema, path, mutation_function)
           when not is_binary(schema) and is_list(path) do
    quote do
      Module.put_attribute(
        __MODULE__,
        :json_ld_fields,
        {unquote(name), {{unquote(schema), unquote(path)}, unquote(mutation_function)}}
      )
    end
  end

  @doc """
  Allows us to have same formatting when adding additional json_ld fields in a controller
  """
  def convert_format(fields) do
    Enum.reduce(fields, [], fn
      {name, {:references, target}}, acc ->
        [{name, {:references, target}} | acc]

      {name, :string, path}, acc when is_list(path) ->
        [{name, {:string, path}} | acc]

      {name, :string, path, mutation_function}, acc when is_list(path) ->
        [{name, {{:string, path}, {:mutator, mutation_function}}} | acc]

      {name, :string, mutation_function}, acc when is_function(mutation_function) ->
        [{name, {:string, mutation_function}} | acc]

      {name, schema, nil}, _acc ->
        raise "=> JSONLD/Schema >> Populating a field as schema requires a populator function - #{
                name
              } - #{inspect(schema)}"

      {name, schema, _}, _acc when is_binary(schema) ->
        raise "=> JSONLD/Schema >> Populating a field as schema requires a schema as second arg - #{
                name
              } - #{inspect(schema)}"

      {name, schema, path}, acc when is_list(path) ->
        [{name, {schema, path}} | acc]

      {name, schema, populator_function}, acc ->
        [{name, {schema, populator_function}} | acc]

      {name, schema, path, mutation_function}, acc
      when not is_binary(schema) and is_list(path) ->
        [{name, {{schema, path}, mutation_function}} | acc]
    end)
  end
end
