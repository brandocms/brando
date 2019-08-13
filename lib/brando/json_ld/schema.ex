defmodule Brando.JSONLD.Schema do
  @moduledoc """

  TODO:
    * a way to reference the `organization` and `creator` @ids.
    * This needs to grab `organization.url` from Brando.Cache
      field "author", references(:identity)
      "author": {
        "@id": "https://univers.agency/#identity"
      },

      field "creator", references(:creator)

      "creator": {
        "@id": "https://univers.agency/#creator"
      },


    All in all should create a

    def __render_json_ld__(record) do
      # this loops through all the fields we have registered for this module
      # :field_name, :type, :path, :fn
    end

    # to populate a string with a path
    # field "description", :string, [:meta_description], &(Brando.HTML.truncate(&1, 155))
    defmacro field(field_name, :string, path, mutation_function) when is_list(path) do
      value = get_in(record, path)
      {field_name, mutation_function.(value)}
    end

    # to populate a schema with a path
    # field "author", "Person", [:author], &(Enum.join([&1.first_name, &1.last_name], " "))
    defmacro field(field_name, schema, path, mutation_function \\ nil) do
      value = get_in(record, path)
      mutated_value = mutation_function && mutation_function.(value) || mutated_value
      {field_name, schema.build(mutated_value)}
    end

    # to populate a schema from data outside of `record`. no path needed.
    # field "organization", "Organization", &Brando.Cache.get(:organization)
    # NOTE: disallow populator_function == nil!
    defmacro field(field_name, schema, populator_function)



      json_ld_schema "ExhibitionEvent" do
        field "startDate", :string, [:programme, :period_begin], &Timex.to_utc/1
        field "endDate", :string, [:programme, :period_end], &Timex.to_utc/1

        field "location",
              JSONLD.Schema.Place,
              &JSONLD.Schema.Place.build(Brando.Cache.get(:organization))

        field "image", JSONLD.Schema.Image, [:cover]
        field "description", :string, [:description], &Brando.HTML.truncate(&1, 155)
        field "artist", JSONLD.Schema.Person, [:artist, :name]
      end

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

  # populate a field as a reference
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
