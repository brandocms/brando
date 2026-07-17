defmodule Brando.Blueprint.Forms.Verifier do
  @moduledoc false

  use Spark.Dsl.Verifier

  alias Brando.Blueprint.Forms
  alias Brando.Blueprint.Relations
  alias Spark.Dsl.Entity
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @many_relation_types [:embeds_many, :entries, :has_many, :many_to_many]
  @one_relation_types [:belongs_to, :embeds_one, :has_one]
  @transformer_asset_types [:image, :video]

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    context = %{
      module: module,
      relations: Verifier.get_entities(dsl_state, [:relations]),
      schema_fields: schema_fields(module)
    }

    dsl_state
    |> Verifier.get_entities([:forms])
    |> validate_entities(&verify_form(context, &1))
  end

  defp verify_form(context, form) do
    inputs = form_inputs(form)

    with :ok <- verify_unique_inputs(context, form, inputs),
         :ok <- validate_entities(inputs, &verify_input(context, form, &1)) do
      validate_entities(form.blocks, &verify_blocks(context, form, &1))
    end
  end

  defp verify_unique_inputs(context, form, inputs) do
    case duplicate_name(inputs) do
      nil ->
        :ok

      name ->
        error(context, form, [form.name, name], "declares form field #{inspect(name)} more than once")
    end
  end

  defp verify_input(context, form, %Forms.Subform{} = subform) do
    with {:ok, relation} <- fetch_subform_relation(context, form, subform),
         :ok <- verify_cardinality(context, form, subform, relation),
         {:ok, related_module} <- fetch_related_schema(context, form, subform, relation),
         :ok <- verify_sub_fields(context, form, subform, related_module) do
      verify_transformer(context, form, subform, relation, related_module)
    end
  end

  defp verify_input(context, form, %Forms.Input{} = input) do
    with :ok <- verify_schema_field(context, form, input),
         :ok <- verify_hidden_field(context, form, input) do
      verify_source_fields(context, form, input)
    end
  end

  defp verify_schema_field(%{schema_fields: schema_fields} = context, form, input) do
    if MapSet.member?(schema_fields, input.name) do
      :ok
    else
      error(context, input, [form.name, input.name], "references unknown schema field #{inspect(input.name)}")
    end
  end

  defp verify_hidden_field(context, form, %{opts: opts} = input) do
    case Keyword.get(opts || [], :hidden) do
      {field, _expected} -> verify_referenced_field(context, form, input, :hidden, field)
      _ -> :ok
    end
  end

  defp verify_source_fields(context, form, %{opts: opts} = input) do
    source = Keyword.get(opts || [], :source, Keyword.get(opts || [], :from))

    source
    |> List.wrap()
    |> validate_entities(&verify_referenced_field(context, form, input, :source, &1))
  end

  defp verify_referenced_field(%{schema_fields: schema_fields} = context, form, input, option, field)
       when is_atom(field) do
    if MapSet.member?(schema_fields, field) do
      :ok
    else
      error(
        context,
        input,
        [form.name, input.name],
        "has #{inspect(option)} referencing unknown schema field #{inspect(field)}"
      )
    end
  end

  defp verify_referenced_field(context, form, input, option, field) do
    error(
      context,
      input,
      [form.name, input.name],
      "has #{inspect(option)} referencing invalid field #{inspect(field)}"
    )
  end

  defp fetch_subform_relation(%{relations: relations} = context, form, subform) do
    case Enum.find(relations, &(&1.name == subform.name)) do
      nil ->
        error(
          context,
          subform,
          [form.name, subform.name],
          "must reference a declared relation; inputs_for cannot target #{inspect(subform.name)}"
        )

      relation ->
        {:ok, relation}
    end
  end

  defp verify_cardinality(_context, _form, %{component: component}, _relation) when not is_nil(component), do: :ok

  defp verify_cardinality(context, form, subform, relation) do
    valid_types = if subform.cardinality == :many, do: @many_relation_types, else: @one_relation_types

    if relation.type in valid_types do
      :ok
    else
      error(
        context,
        subform,
        [form.name, subform.name],
        "uses cardinality #{inspect(subform.cardinality)} for #{inspect(relation.type)} relation #{inspect(relation.name)}"
      )
    end
  end

  defp fetch_related_schema(context, form, subform, relation) do
    related_module = Map.get(relation.opts, :module)

    if is_atom(related_module) and Code.ensure_loaded?(related_module) and
         function_exported?(related_module, :__schema__, 1) do
      {:ok, related_module}
    else
      error(
        context,
        subform,
        [form.name, subform.name],
        "references relation #{inspect(relation.name)} without a loaded Ecto schema module"
      )
    end
  end

  defp verify_sub_fields(context, form, subform, related_module) do
    related_fields = schema_fields(related_module)

    validate_entities(subform.sub_fields, fn input ->
      if MapSet.member?(related_fields, input.name) do
        :ok
      else
        error(
          context,
          input,
          [form.name, subform.name, input.name],
          "references unknown field #{inspect(input.name)} on #{inspect(related_module)}"
        )
      end
    end)
  end

  defp verify_transformer(_context, _form, %{style: style}, _relation, _related_module)
       when not is_tuple(style),
       do: :ok

  defp verify_transformer(context, form, subform, relation, related_module) do
    with :ok <- verify_transformer_relation(context, form, subform, relation),
         :ok <- verify_transformer_component(context, form, subform),
         {:ok, fields} <- transformer_fields(context, form, subform) do
      verify_transformer_assets(context, form, subform, related_module, fields)
    end
  end

  defp verify_transformer_relation(context, form, subform, %{type: type})
       when type not in [:embeds_many, :has_many] do
    error(
      context,
      subform,
      [form.name, subform.name],
      "transformers require a has_many or embeds_many relation, got #{inspect(type)}"
    )
  end

  defp verify_transformer_relation(_context, _form, _subform, _relation), do: :ok

  defp verify_transformer_component(context, form, %{component: component} = subform)
       when not is_nil(component) do
    error(
      context,
      subform,
      [form.name, subform.name],
      "cannot combine transformer style with a custom component"
    )
  end

  defp verify_transformer_component(_context, _form, _subform), do: :ok

  defp transformer_fields(context, form, %{style: {:transformer, fields}} = subform) do
    fields = List.wrap(fields)

    cond do
      fields == [] ->
        error(context, subform, [form.name, subform.name], "transformer requires at least one asset field")

      Enum.uniq(fields) != fields ->
        error(context, subform, [form.name, subform.name], "transformer asset fields must be unique")

      true ->
        {:ok, fields}
    end
  end

  defp verify_transformer_assets(context, form, subform, related_module, fields) do
    if Brando.Blueprint.blueprint?(related_module) do
      fields
      |> Enum.map(&{&1, Brando.Blueprint.Assets.__asset__(related_module, &1)})
      |> verify_resolved_transformer_assets(context, form, subform, related_module)
    else
      error(
        context,
        subform,
        [form.name, subform.name],
        "transformer relation module #{inspect(related_module)} must be a Brando Blueprint"
      )
    end
  end

  defp verify_resolved_transformer_assets(assets, context, form, subform, related_module) do
    case Enum.find(assets, fn {_field, asset} -> is_nil(asset) or asset.type not in @transformer_asset_types end) do
      {field, nil} ->
        error(
          context,
          subform,
          [form.name, subform.name],
          "transformer references unknown asset #{inspect(field)} on #{inspect(related_module)}"
        )

      {field, asset} ->
        error(
          context,
          subform,
          [form.name, subform.name],
          "transformer asset #{inspect(field)} must be an image or video, got #{inspect(asset.type)}"
        )

      nil ->
        verify_unique_transformer_asset_types(assets, context, form, subform)
    end
  end

  defp verify_unique_transformer_asset_types(assets, context, form, subform) do
    types = Enum.map(assets, fn {_field, asset} -> asset.type end)

    if Enum.uniq(types) == types do
      :ok
    else
      error(
        context,
        subform,
        [form.name, subform.name],
        "transformer accepts at most one image field and one video field"
      )
    end
  end

  defp verify_blocks(context, form, block_input) do
    relation = Enum.find(context.relations, &(&1.name == block_input.name))

    cond do
      not match?(%Relations.Relation{type: :has_many, opts: %{module: :blocks}}, relation) ->
        error(
          context,
          block_input,
          [form.name, block_input.name],
          "blocks input must reference a has_many relation with `module: :blocks`"
        )

      not context.module.has_trait(Brando.Trait.Blocks) ->
        error(
          context,
          block_input,
          [form.name, block_input.name],
          "blocks input requires the Brando.Trait.Blocks trait"
        )

      true ->
        verify_hidden_field(context, form, block_input)
    end
  end

  defp schema_fields(module) do
    module
    |> then(&(&1.__schema__(:fields) ++ &1.__schema__(:associations) ++ &1.__schema__(:embeds)))
    |> MapSet.new()
  end

  defp form_inputs(form) do
    for tab <- form.tabs,
        fieldset <- tab.fields,
        input <- fieldset.fields,
        do: input
  end

  defp duplicate_name(entities) do
    entities
    |> Enum.map(& &1.name)
    |> Enum.frequencies()
    |> Enum.find_value(fn
      {name, count} when count > 1 -> name
      _ -> nil
    end)
  end

  defp validate_entities(entities, validator) do
    Enum.reduce_while(entities, :ok, fn entity, :ok ->
      case validator.(entity) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp error(%{module: module}, entity, path, message) do
    {:error,
     DslError.exception(
       module: module,
       path: [:forms | path],
       location: Entity.anno(entity),
       message: message
     )}
  end
end
