defmodule Brando.Blueprint.SecondaryVerifier.Metadata do
  @moduledoc false

  alias Brando.Blueprint.SecondaryVerifier.Support
  alias Spark.Dsl.Verifier

  @json_ld_context_types [:current_url, :identity, :language]
  @json_ld_value_types [:date, :datetime, :image, :integer, :string]

  @doc false
  def verify(dsl_state) do
    with :ok <- verify_meta_schemas(dsl_state) do
      verify_json_ld_schemas(dsl_state)
    end
  end

  defp verify_meta_schemas(dsl_state) do
    case Verifier.get_entities(dsl_state, [:meta_schemas]) do
      [] ->
        :ok

      [schema] ->
        Support.validate_entities(schema.fields, &verify_meta_field(dsl_state, &1))

      [_first, duplicate | _rest] ->
        Support.error(
          dsl_state,
          [:meta_schemas],
          duplicate,
          "only one `meta_schema` can be declared because metadata extraction returns one schema"
        )
    end
  end

  defp verify_meta_field(dsl_state, field) do
    targets = List.wrap(field.targets)

    if targets != [] and Enum.all?(targets, &Support.non_empty_string?/1) do
      :ok
    else
      Support.error(
        dsl_state,
        [:meta_schemas, :field],
        field,
        "meta field targets must be a non-empty string or non-empty list of strings"
      )
    end
  end

  defp verify_json_ld_schemas(dsl_state) do
    case Verifier.get_entities(dsl_state, [:json_ld_schemas]) do
      [] ->
        :ok

      [schema] ->
        verify_json_ld_schema(dsl_state, schema)

      [_first, duplicate | _rest] ->
        Support.error(
          dsl_state,
          [:json_ld_schemas, duplicate.schema],
          duplicate,
          "only one `json_ld_schema` can be declared because extraction returns one entity"
        )
    end
  end

  defp verify_json_ld_schema(dsl_state, schema) do
    with {:ok, schema_fields} <- json_ld_schema_fields(dsl_state, schema),
         :ok <- verify_unique_json_ld_fields(dsl_state, schema) do
      Support.validate_entities(schema.fields, &verify_json_ld_field(dsl_state, schema, schema_fields, &1))
    end
  end

  defp json_ld_schema_fields(dsl_state, schema) do
    if Support.struct_module?(schema.schema) do
      schema_module = schema.schema
      {:ok, schema_module.__struct__() |> Map.keys() |> MapSet.new()}
    else
      Support.error(
        dsl_state,
        [:json_ld_schemas, schema.schema],
        schema,
        "JSON-LD schema #{inspect(schema.schema)} must be an available struct module"
      )
    end
  end

  defp verify_unique_json_ld_fields(dsl_state, schema) do
    case Support.find_duplicate(schema.fields, & &1.name) do
      nil ->
        :ok

      field ->
        Support.error(
          dsl_state,
          [:json_ld_schemas, schema.schema, :field, field.name],
          field,
          "JSON-LD field #{inspect(field.name)} is declared more than once"
        )
    end
  end

  defp verify_json_ld_field(dsl_state, schema, schema_fields, field) do
    path = [:json_ld_schemas, schema.schema, :field, field.name]

    with :ok <- Support.verify_key(dsl_state, path, field, "JSON-LD field", field.name),
         :ok <- verify_json_ld_field_exists(dsl_state, path, field, schema.schema, schema_fields) do
      verify_json_ld_field_type(dsl_state, path, field)
    end
  end

  defp verify_json_ld_field_exists(dsl_state, path, field, schema, schema_fields) do
    if MapSet.member?(schema_fields, field.name) do
      :ok
    else
      Support.error(
        dsl_state,
        path,
        field,
        "JSON-LD field #{inspect(field.name)} does not exist on #{inspect(schema)}"
      )
    end
  end

  defp verify_json_ld_field_type(_dsl_state, _path, %{type: type, value_fn: nil})
       when type in @json_ld_context_types,
       do: :ok

  defp verify_json_ld_field_type(dsl_state, path, %{type: type} = field)
       when type in @json_ld_context_types do
    Support.error(
      dsl_state,
      path,
      field,
      "JSON-LD type #{inspect(type)} derives its value and does not accept a callback"
    )
  end

  defp verify_json_ld_field_type(dsl_state, path, %{type: type, value_fn: nil} = field)
       when type in @json_ld_value_types do
    Support.error(dsl_state, path, field, "JSON-LD type #{inspect(type)} requires a value callback")
  end

  defp verify_json_ld_field_type(_dsl_state, _path, %{type: type}) when type in @json_ld_value_types,
    do: :ok

  defp verify_json_ld_field_type(dsl_state, path, %{type: {:list, module}, value_fn: value_fn} = field) do
    with :ok <- verify_json_ld_value_callback(dsl_state, path, field, value_fn) do
      verify_json_ld_builder(dsl_state, path, field, module)
    end
  end

  defp verify_json_ld_field_type(dsl_state, path, %{type: type} = field) when is_tuple(type) do
    Support.error(
      dsl_state,
      path,
      field,
      "unsupported JSON-LD field type #{inspect(type)}; use `{:list, SchemaModule}`"
    )
  end

  defp verify_json_ld_field_type(dsl_state, path, %{type: module, value_fn: value_fn} = field) do
    with :ok <- verify_json_ld_value_callback(dsl_state, path, field, value_fn) do
      verify_json_ld_builder(dsl_state, path, field, module)
    end
  end

  defp verify_json_ld_value_callback(dsl_state, path, field, nil) do
    Support.error(dsl_state, path, field, "nested JSON-LD schema fields require a value callback")
  end

  defp verify_json_ld_value_callback(_dsl_state, _path, _field, _value_fn), do: :ok

  defp verify_json_ld_builder(dsl_state, path, field, module) do
    if Support.callback_module?(module, :build, 1) do
      :ok
    else
      Support.error(
        dsl_state,
        path,
        field,
        "nested JSON-LD schema #{inspect(module)} must be an available module exporting `build/1`"
      )
    end
  end
end
