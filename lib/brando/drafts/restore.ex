defmodule Brando.Drafts.Restore do
  @moduledoc "Preflights recovery copies and builds editor changesets without writing content."
  alias Brando.Drafts.Modules
  alias Ecto.Changeset

  def prepare(draft, entry, schema, user, opts \\ []) do
    with :ok <- format(draft),
         :ok <- schema_version(draft, schema) do
      {blocks, issues} = Modules.check(draft.payload["blocks"] || %{}, draft.payload["modules"] || %{})
      conflict? = draft.base_fingerprint != Brando.Drafts.fingerprint(entry)

      cond do
        conflict? && !opts[:accept_conflict] ->
          {:review, :entry_changed, issues}

        issues != [] && !opts[:compatible_only] ->
          {:review, :modules_changed, issues}

        true ->
          block_fields = Map.keys(blocks)
          params = draft.payload["main"] || %{}
          params = Map.merge(params, draft.payload["transformers"] || %{})
          params = reconcile(params, entry) |> Map.drop(["id", "creator_id", "deleted_at"])
          changeset = schema.changeset(entry, params, user)

          changeset =
            Enum.reduce(block_fields, changeset, fn field, cs ->
              assoc =
                Enum.find(schema.__schema__(:associations), &(to_string(&1) == "entry_#{field}")) ||
                  raise "Unknown block field"

              join_schema = schema.__schema__(:association, assoc).queryable
              existing = Map.get(entry, assoc) || []

              rows =
                Enum.map(blocks[field], fn row ->
                  base = Enum.find(existing, &(to_string(&1.id) == to_string(row["id"]))) || struct(join_schema)
                  row = reconcile(row, base)
                  row = Map.put(row, "block", put_source(row["block"], join_schema))
                  join_schema.changeset(base, row, user.id, true)
                end)

              Changeset.put_assoc(cs, assoc, rows)
            end)

          {:ok, changeset, issues}
      end
    end
  rescue
    _ -> {:error, "This recovery copy could not be applied. Its contents are still available below."}
  end

  defp format(%{format_version: 1, payload: %{"main" => main, "blocks" => blocks}}) when is_map(main) and is_map(blocks),
    do: :ok

  defp format(_), do: {:error, "This recovery copy uses an unsupported format. Its contents are still available below."}

  defp schema_version(draft, schema) do
    if draft.schema_version == Brando.Blueprint.Snapshot.get_current_version(schema),
      do: :ok,
      else:
        {:error,
         "The entry schema changed since this copy was saved. You can copy its contents below or open a clean editor."}
  end

  # Only identities that still belong to the current association may survive.
  # Removed rows become new rows; owner FKs and migration stamps are server-owned.
  def reconcile(params, %schema{} = base) when is_map(params) do
    associations = schema.__schema__(:associations)
    embeds = schema.__schema__(:embeds)
    fields = schema.__schema__(:fields) ++ schema.__schema__(:virtual_fields) ++ associations
    allowed = Enum.map(fields, &to_string/1)

    params
    |> Map.take(allowed)
    |> Map.drop(if(schema == Brando.Content.Block, do: [], else: ["module_id", "block_id", "table_row_id"]))
    |> Map.drop([
      "creator_id",
      "parent_id",
      "entry_id",
      "module_version",
      "source",
      "deleted_at",
      "password",
      "password_confirmation",
      "password_hash"
    ])
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      field = Enum.find(fields, &(to_string(&1) == key))

      value =
        cond do
          field in associations ->
            reconcile_relation(value, Map.get(base, field), schema.__schema__(:association, field).queryable)

          field in embeds ->
            value

          key == "id" ->
            base.id

          true ->
            value
        end

      Map.put(acc, key, value)
    end)
  end

  defp reconcile_relation(rows, current, schema) when is_list(rows) do
    current = if is_list(current), do: current, else: []

    Enum.map(rows, fn params ->
      base = Enum.find(current, &(Map.get(&1, :id) && to_string(&1.id) == to_string(params["id"]))) || struct(schema)
      reconcile(params, base)
    end)
  end

  defp reconcile_relation(params, current, schema) when is_map(params) do
    base = if is_struct(current, schema), do: current, else: struct(schema)
    reconcile(params, base)
  end

  defp reconcile_relation(value, _current, _schema), do: value

  defp put_source(block, source) do
    block
    |> Map.put("source", to_string(source))
    |> Map.update("children", [], &Enum.map(&1, fn child -> put_source(child, source) end))
  end
end
