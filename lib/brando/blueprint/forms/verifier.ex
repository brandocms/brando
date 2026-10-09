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

    forms = Verifier.get_entities(dsl_state, [:forms])

    with :ok <- validate_entities(forms, &verify_form(context, &1)) do
      case Enum.flat_map(forms, &deprecated_ai_warnings/1) do
        [] -> :ok
        warnings -> {:warn, warnings}
      end
    end
  end

  defp verify_form(context, form) do
    inputs = form_inputs(form)

    with :ok <- verify_static_query(context, form),
         :ok <- verify_unique_inputs(context, form, inputs),
         :ok <- validate_entities(inputs, &verify_input(context, form, &1)) do
      validate_entities(form.blocks, &verify_blocks(context, form, &1))
    end
  end

  defp verify_static_query(context, %{query: query} = form) when is_map(query) do
    case Map.fetch(query, :matches) do
      :error -> :ok
      {:ok, matches} when is_map(matches) -> :ok
      {:ok, matches} -> error(context, form, [form.name], "static query :matches must be a map, got #{inspect(matches)}")
    end
  end

  defp verify_static_query(_context, _form), do: :ok

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
         :ok <- verify_sub_fields(context, form, subform, related_module),
         :ok <- verify_listing(context, form, subform) do
      verify_transformer(context, form, subform, relation, related_module)
    end
  end

  defp verify_input(context, form, %Forms.Input{} = input) do
    with :ok <- verify_schema_field(context, form, input),
         :ok <- verify_hidden_field(context, form, input),
         :ok <- verify_source_fields(context, form, input),
         :ok <- verify_ai_actions(context, form, input) do
      verify_write_with_ai(context, form, input)
    end
  end

  # `write_with_ai: [from: …]` reads fields as an AI action does. Not checked
  # when it comes from a deprecated `ai:`, whose `context:` never was.
  defp verify_write_with_ai(context, form, %{ai: nil, opts: opts} = input) do
    case Keyword.get(opts || [], :write_with_ai) do
      config when is_list(config) ->
        validate_entities(Keyword.get(config, :from, []), &verify_write_with_ai_source(context, form, input, &1))

      _ ->
        :ok
    end
  end

  defp verify_write_with_ai(_context, _form, _input), do: :ok

  defp verify_write_with_ai_source(context, form, input, field) do
    case ai_source_problem(context, field) do
      nil -> :ok
      problem -> error(context, input, [form.name, input.name], "has write_with_ai reading #{problem}")
    end
  end

  # `ai_actions:` read the fields in `from:`: the schema's own values and its
  # block fields. `:blocks` stands for every block field, so it needs one,
  # whatever the relation is called. Associations and embeds are not text to
  # give a model.
  # Actions from the deprecated `ai:` are not checked: `context:` was never
  # checked, and a Blueprint that compiled before must still compile.
  defp verify_ai_actions(context, form, %{actions: actions} = input) do
    actions
    |> Enum.filter(&(&1.origin == :ai_actions))
    |> validate_entities(fn action ->
      validate_entities(action.from, &verify_ai_action_source(context, form, input, action, &1))
    end)
  end

  defp verify_ai_action_source(context, form, input, action, field) do
    case ai_source_problem(context, field) do
      nil ->
        :ok

      problem ->
        error(context, input, [form.name, input.name], "has ai_actions #{inspect(action.name)} reading #{problem}")
    end
  end

  # Why `field` cannot be read as text for a model, or nil when it can.
  defp ai_source_problem(context, field) do
    cond do
      ai_readable_field?(context.module, field) -> nil
      Enum.any?(context.relations, &(block_relation?(&1) and (field == :blocks or &1.name == field))) -> nil
      MapSet.member?(context.schema_fields, field) -> "#{inspect(field)} in :from, which is not a text or block field"
      true -> "unknown field #{inspect(field)} in :from"
    end
  end

  defp ai_readable_field?(module, field) do
    field in (module.__schema__(:fields) ++ module.__schema__(:virtual_fields)) and
      field not in module.__schema__(:embeds)
  end

  defp block_relation?(relation), do: match?(%Relations.Relation{type: :has_many, opts: %{module: :blocks}}, relation)

  defp verify_schema_field(%{schema_fields: schema_fields} = context, form, input) do
    if MapSet.member?(schema_fields, input.name) do
      :ok
    else
      error(context, input, [form.name, input.name], "references unknown schema field #{inspect(input.name)}")
    end
  end

  defp verify_hidden_field(context, form, %{opts: opts} = input) do
    for option <- [:hidden, :show_if],
        {field, _expected} <- [Keyword.get(opts || [], option)],
        reduce: :ok do
      :ok -> verify_referenced_field(context, form, input, option, field)
      error -> error
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
      cond do
        match?(%Forms.Input{}, input) and Enum.any?(input.actions, &(&1.origin == :ai_actions)) ->
          error(
            context,
            input,
            [form.name, subform.name, input.name],
            "ai_actions work only on top-level inputs, not in inputs_for"
          )

        MapSet.member?(related_fields, input.name) ->
          verify_sub_field_visibility(context, form, subform, input, related_fields, related_module)

        true ->
          error(
            context,
            input,
            [form.name, subform.name, input.name],
            "references unknown field #{inspect(input.name)} on #{inspect(related_module)}"
          )
      end
    end)
  end

  # `hidden: {field, _}` / `show_if: {field, _}` in a subform refer to the
  # row's own fields.
  defp verify_sub_field_visibility(context, form, subform, %{opts: opts} = input, related_fields, related_module) do
    for option <- [:hidden, :show_if],
        {field, _expected} <- [Keyword.get(opts || [], option)],
        reduce: :ok do
      :ok ->
        if is_atom(field) and MapSet.member?(related_fields, field),
          do: :ok,
          else:
            error(
              context,
              input,
              [form.name, subform.name, input.name],
              "has #{inspect(option)} referencing unknown field #{inspect(field)} on #{inspect(related_module)}"
            )

      error ->
        error
    end
  end

  defp verify_listing(context, form, %{style: :listing} = subform) do
    cond do
      subform.cardinality != :many ->
        error(context, subform, [form.name, subform.name], "listing style requires cardinality :many")

      not is_nil(subform.component) ->
        error(context, subform, [form.name, subform.name], "cannot combine listing style with a custom component")

      is_nil(subform.listing) ->
        error(context, subform, [form.name, subform.name], "listing style requires a listing function component")

      true ->
        :ok
    end
  end

  defp verify_listing(_context, _form, _subform), do: :ok

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

  # Virtual fields too: a form may carry one (a hidden input the changeset
  # reads back), and Ecto lists those apart from `:fields`.
  defp schema_fields(module) do
    module
    |> then(
      &(&1.__schema__(:fields) ++
          &1.__schema__(:virtual_fields) ++ &1.__schema__(:associations) ++ &1.__schema__(:embeds))
    )
    |> MapSet.new()
  end

  # `ai:` on an input is deprecated: a warning at the input, with the
  # `ai_actions:` it runs as and should be written as, or why it does nothing.
  defp deprecated_ai_warnings(form) do
    top_level =
      for %Forms.Input{ai: ai} = input <- form_inputs(form), not is_nil(ai), built_in?(input) do
        {deprecated_ai_message(input), Entity.anno(input)}
      end

    nested =
      for %Forms.Subform{sub_fields: sub_fields} <- form_inputs(form),
          %Forms.Input{ai: ai} = input <- sub_fields || [],
          not is_nil(ai),
          built_in?(input) do
        {"input #{inspect(input.name)} in inputs_for has `ai:`, which is deprecated and does nothing there. Remove it.",
         Entity.anno(input)}
      end

    top_level ++ nested
  end

  # A custom component (`{:live_component, module}`, a function) gets `ai:`
  # in its options as before, and may read it: no warning.
  defp built_in?(%Forms.Input{type: type}), do: is_atom(type)

  @subject "has `ai:`, which is deprecated and will be removed"

  defp deprecated_ai_message(%Forms.Input{type: :rich_text, name: name, ai: ai, opts: opts}) do
    converted = Forms.WriteWithAI.from_ai(ai)

    cond do
      opts[:write_with_ai] != converted ->
        "input #{inspect(name)} #{@subject}. `write_with_ai:` is set, so it is ignored. Remove it."

      source = Forms.WriteWithAI.to_source(converted) ->
        [
          "input #{inspect(name)} #{@subject}. On a rich text input it gives Write with AI its instructions, the fields they read and its model. Write it as:",
          indent(source),
          dropped_options_note("write_with_ai:", Keyword.take(converted, Forms.AIAction.request_opt_keys()))
        ]
        |> Enum.filter(& &1)
        |> Enum.join("\n\n")

      true ->
        "input #{inspect(name)} #{@subject}. It gives Write with AI no instructions, and Write with AI is on whenever AI is configured. Remove it."
    end
  end

  defp deprecated_ai_message(%Forms.Input{name: name, type: type, ai: ai, actions: actions}) do
    subject = "input #{inspect(name)} #{@subject}"

    case Enum.find(actions, &(&1.origin == :ai)) do
      %Forms.AIAction{} = action ->
        [
          "#{subject}. It runs as the AI action \"Generate\", whose result the editor reviews before it reaches the field. Write it as:",
          indent(Forms.AIAction.to_source(action)),
          action.from == [] &&
            "Add `from:` with the fields the prompt reads: `ai_actions:` requires them, and `ai:` named none in `context:`.",
          dropped_options_note("ai_actions:", action.request_opts)
        ]
        |> Enum.filter(& &1)
        |> Enum.join("\n\n")

      nil ->
        "#{subject}. #{ignored_reason(type, name, ai, actions)} Remove it."
    end
  end

  defp ignored_reason(type, name, ai, actions) do
    cond do
      not Forms.AIAction.takes_actions?(type, name) -> "It does nothing on a #{inspect(type)} input."
      Enum.any?(actions, &(&1.name == :generate)) -> "`ai_actions:` already has a :generate action, so it is ignored."
      is_nil(Forms.AIAction.generate(ai, :ai)) -> "It has no prompt, so it does nothing."
      true -> "It does nothing."
    end
  end

  defp dropped_options_note(_option, []), do: nil

  defp dropped_options_note(option, opts) do
    keys = opts |> Keyword.keys() |> Enum.map_join(", ", &"`#{&1}`")

    "`#{option}` takes no #{keys}: set API keys under `providers:` and request options under `default_opts:` in `config :brando, Brando.AI`. Until `ai:` is removed, they are kept."
  end

  defp indent(source), do: source |> String.split("\n") |> Enum.map_join("\n", &("    " <> &1))

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
