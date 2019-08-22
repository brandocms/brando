defmodule Brando.JSONLD.Schema do
  @moduledoc """
  Schema definitions for JSONLD schemas
  """

  @doc false
  defmacro __using__(_) do
    quote do
      import Brando.JSONLD.Schema, only: [json_ld_schema: 2]
      Module.register_attribute(__MODULE__, :json_ld_fields, accumulate: true)
    end
  end

  defmacro json_ld_schema(schema_module, do: block) do
    do_json_ld_schema(schema_module, block)
  end

  defp do_json_ld_schema(schema_module, block) do
    prelude =
      quote do
        Module.put_attribute(__MODULE__, :json_ld_schema, unquote(schema_module))

        try do
          import Brando.JSONLD.Schema
          unquote(block)
        after
          :ok
        end
      end

    postlude =
      quote unquote: false do
        fields = @json_ld_fields |> Enum.reverse()
        schema = @json_ld_schema

        def __json_ld_schema__(:fields), do: unquote(fields)
        def __json_ld_schema__(:schema), do: unquote(schema)

        def extract_json_ld(data) do
          Brando.JSONLD.Schema.extract_json_ld(__MODULE__, data)
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
  defmacro field(name, {:references, target}) do
    quote do
      Module.put_attribute(__MODULE__, :json_ld_fields, unquote(name))

      def __json_ld_field__(unquote(name), data) do
        %{"@id": "#{Brando.Utils.hostname()}/##{unquote(target)}"}
      end
    end
  end

  # populate a field with a path without mutator function
  defmacro field(name, :string, path) when is_list(path) do
    quote do
      Module.put_attribute(__MODULE__, :json_ld_fields, unquote(name))

      def __json_ld_field__(unquote(name), data) do
        get_in(data, Enum.map(unquote(path), &Access.key/1))
      end
    end
  end

  # populate a field with a path with mutator function
  defmacro field(name, :string, path, mutation_function) when is_list(path) do
    quote do
      Module.put_attribute(__MODULE__, :json_ld_fields, unquote(name))

      def __json_ld_field__(unquote(name), data) do
        value = get_in(data, Enum.map(unquote(path), &Access.key/1))
        unquote(mutation_function).(value)
      end
    end
  end

  # populate a field without a path with mutator function
  defmacro field(name, :string, mutation_function) do
    quote do
      Module.put_attribute(__MODULE__, :json_ld_fields, unquote(name))

      def __json_ld_field__(unquote(name), data) do
        unquote(mutation_function).(data)
      end
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
      Module.put_attribute(__MODULE__, :json_ld_fields, unquote(name))

      def __json_ld_field__(unquote(name), data) do
        value = get_in(data, Enum.map(unquote(path), &Access.key/1))
        unquote(schema).build(value)
      end
    end
  end

  defmacro field(name, schema, populator_function) do
    quote do
      Module.put_attribute(__MODULE__, :json_ld_fields, unquote(name))

      def __json_ld_field__(unquote(name), data) do
        pf_result = unquote(populator_function).(data)
        unquote(schema).build(pf_result)
      end
    end
  end

  # populate a field as a schema with a path and populator function
  defmacro field(name, schema, path, mutation_function)
           when not is_binary(schema) and is_list(path) do
    quote do
      Module.put_attribute(__MODULE__, :json_ld_fields, unquote(name))

      def __json_ld_field__(unquote(name), data) do
        value = get_in(data, Enum.map(unquote(path), &Access.key/1))
        mf_result = unquote(mutation_function).(value)
        unquote(schema).build(mf_result)
      end
    end
  end

  def extract_json_ld(mod, data) do
    Enum.reduce(
      mod.__json_ld_schema__(:fields),
      struct(mod.__json_ld_schema__(:schema)),
      fn name, acc ->
        Map.put(acc, name, mod.__json_ld_field__(name, data))
      end
    )
  end
end
