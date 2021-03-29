defmodule Brando.Blueprint.JSONLD do
  # coveralls-ignore-start
  defmacro json_ld_schema(schema_module, do: block) do
    do_json_ld_schema(schema_module, block)
  end

  # coveralls-ignore-stop

  defp do_json_ld_schema(schema_module, block) do
    prelude =
      quote do
        Module.put_attribute(__MODULE__, :json_ld_schema, unquote(schema_module))

        try do
          unquote(block)
        after
          :ok
        end
      end

    postlude =
      quote do
        def extract_json_ld(data, extra_fields \\ []) do
          fields = @json_ld_fields ++ extra_fields

          Enum.reduce(fields, struct(@json_ld_schema), fn
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

    quote do
      unquote(prelude)
      unquote(postlude)
    end
  end

  @doc """
  Defines a JSON LD field.

  This macro defines

    * a field name
    * a path to extract the data from
    * a mutator/generator function
  """
  defmacro json_ld_field(name, {:references, target}) do
    quote do
      Module.put_attribute(
        __MODULE__,
        :json_ld_fields,
        {unquote(name), {:references, unquote(target)}}
      )
    end
  end

  # populate a field with a path without mutator function
  defmacro json_ld_field(name, :string, path) when is_list(path) do
    quote do
      Module.put_attribute(
        __MODULE__,
        :json_ld_fields,
        {unquote(name), {:string, unquote(path)}}
      )
    end
  end

  # populate a field with a path with mutator function
  defmacro json_ld_field(name, :string, path, mutation_function) when is_list(path) do
    quote do
      Module.put_attribute(
        __MODULE__,
        :json_ld_fields,
        {unquote(name), {{:string, unquote(path)}, {:mutator, unquote(mutation_function)}}}
      )
    end
  end

  # populate a field without a path with mutator function
  defmacro json_ld_field(name, :string, mutation_function) when is_function(mutation_function) do
    quote do
      Module.put_attribute(
        __MODULE__,
        :json_ld_fields,
        {unquote(name), {:string, unquote(mutation_function)}}
      )
    end
  end

  # populate a field as a schema with populator function
  defmacro json_ld_field(name, schema, nil) do
    raise "=> JSONLD/Schema >> Populating a field as schema requires a populator function - #{
            name
          } - #{inspect(schema)}"
  end

  defmacro json_ld_field(name, schema, _) when is_binary(schema) do
    raise "=> JSONLD/Schema >> Populating a field as schema requires a schema as second arg - #{
            name
          } - #{inspect(schema)}"
  end

  defmacro json_ld_field(name, schema, path) when is_list(path) do
    quote do
      Module.put_attribute(
        __MODULE__,
        :json_ld_fields,
        {unquote(name), {unquote(schema), unquote(path)}}
      )
    end
  end

  defmacro json_ld_field(name, schema, populator_function) do
    quote do
      Module.put_attribute(
        __MODULE__,
        :json_ld_fields,
        {unquote(name), {unquote(schema), unquote(populator_function)}}
      )
    end
  end

  # populate a field as a schema with a path and populator function
  defmacro json_ld_field(name, schema, path, mutation_function)
           when not is_binary(schema) and is_list(path) do
    quote do
      Module.put_attribute(
        __MODULE__,
        :json_ld_fields,
        {unquote(name), {{unquote(schema), unquote(path)}, unquote(mutation_function)}}
      )
    end
  end
end
