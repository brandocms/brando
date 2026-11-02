defmodule Brando.Content.Definition.Params do
  @moduledoc false

  alias Brando.Content.Definition.{Model, References}
  alias Brando.Content.{Module, RefGuard, TableTemplate}
  alias Brando.Content.Var.ValidateValue
  alias Ecto.Changeset

  def changeset(definition, record, references, creator, tables, parent_id \\ nil) do
    vars = association(definition["vars"], loaded(record, :vars), "key", references)

    case definition["kind"] do
      "table_template" ->
        attrs = definition |> Map.take(~w(uid name)) |> Map.put("vars", vars)

        (record || struct(TableTemplate))
        |> TableTemplate.changeset(attrs, creator)
        |> read_stored_defaults()

      "module" ->
        refs = association(definition["refs"], loaded(record, :refs), "uid", references)

        attrs =
          definition
          |> Map.take(Enum.map(Model.module_fields(), &to_string/1))
          |> Map.merge(%{"vars" => vars, "refs" => refs})

        table_id = if uid = definition["table_template"], do: Map.get(tables, uid), else: nil

        Module.changeset(record || struct(Module), attrs, creator)
        |> read_stored_defaults()
        |> Changeset.put_change(:table_template_id, table_id)
        |> Changeset.put_change(:parent_id, parent_id)
    end
  end

  # A definition's default is read as it is, as `Model` reads it: a stored one
  # whose option has gone must not stop the import. A has_many cast takes no
  # options, so the check comes off here.
  defp read_stored_defaults(%Changeset{changes: %{vars: vars}} = changeset) do
    vars = Enum.map(vars, &(&1 |> ValidateValue.forget_error() |> RefGuard.revalidate()))
    RefGuard.revalidate(%{changeset | changes: %{changeset.changes | vars: vars}})
  end

  defp read_stored_defaults(changeset), do: changeset

  defp loaded(nil, _field), do: []
  defp loaded(record, field), do: Map.fetch!(record, field)

  defp association(definitions, records, identity, references) do
    identity_atom = String.to_existing_atom(identity)
    existing = Map.new(records, &{Map.fetch!(&1, identity_atom), &1})

    Enum.map(definitions, fn definition ->
      record = Map.get(existing, definition[identity])
      assets = References.decode!(definition["assets"], references)
      params = definition |> Map.delete("assets") |> Map.merge(assets)

      params =
        if Map.has_key?(params, "data"),
          do: Map.update!(params, "data", &References.decode_data!(&1, references)),
          else: params

      params = attach_embed_ids(params, record)
      if record, do: Map.put(params, "id", record.id), else: params
    end)
  end

  # Canonical definitions omit embedded Ecto PKs. Reattach local ones on update
  # so embeds are matched without exporting installation-specific identities.
  defp attach_embed_ids(params, nil), do: params

  defp attach_embed_ids(params, %{__struct__: schema} = record) do
    params =
      Enum.reduce(schema.__schema__(:primary_key), params, fn key, attrs ->
        Map.put(attrs, to_string(key), Map.get(record, key))
      end)

    Enum.reduce(schema.__schema__(:fields), params, fn field, attrs ->
      attach_field_embed_ids(attrs, to_string(field), Map.get(record, field))
    end)
  end

  defp attach_embed_ids(params, _), do: params

  defp attach_field_embed_ids(attrs, key, value) do
    case {Map.get(attrs, key), value} do
      {input, %{__struct__: nested}} when is_map(input) ->
        if function_exported?(nested, :__schema__, 1),
          do: Map.put(attrs, key, attach_embed_ids(input, value)),
          else: attrs

      {inputs, records} when is_list(inputs) and is_list(records) ->
        Map.put(
          attrs,
          key,
          inputs
          |> Enum.with_index()
          |> Enum.map(fn {input, index} -> attach_embed_ids(input, Enum.at(records, index)) end)
        )

      _ ->
        attrs
    end
  end
end
