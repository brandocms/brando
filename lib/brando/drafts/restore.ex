defmodule Brando.Drafts.Restore do
  @moduledoc "Preflights recovery copies and builds editor changesets without writing content."
  alias Brando.Drafts.Modules
  alias Ecto.Changeset

  def prepare(draft, entry, schema, user, opts \\ []) do
    with :ok <- format(draft),
         :ok <- schema_version(draft, schema) do
      {blocks, issues} =
        Modules.check(draft.payload["blocks"] || %{}, draft.payload["modules"] || %{}, keep_saved: opts[:keep_saved])

      conflict? = draft.base_fingerprint != Brando.Drafts.fingerprint(entry)

      cond do
        conflict? && !opts[:accept_conflict] ->
          {:review, :entry_changed, issues}

        issues != [] && !opts[:compatible_only] ->
          {:review, :modules_changed, issues}

        true ->
          {:ok, build_changeset(draft, entry, schema, user, blocks), issues}
      end
    end
  rescue
    _ -> {:error, "This recovery copy could not be applied. Its contents are still available below."}
  end

  defp build_changeset(draft, entry, schema, user, blocks) do
    params = draft.payload["main"] || %{}
    params = Map.merge(params, draft.payload["transformers"] || %{})
    params = reconcile(params, entry) |> Map.drop(["id", "creator_id", "deleted_at"])
    changeset = schema.changeset(entry, params, user)

    blocks
    |> Map.keys()
    |> Enum.reduce(changeset, &put_block_field(&2, &1, blocks[&1], entry, schema, user))
    |> load_moved_relations()
  end

  # Each row is cast onto the saved row it restores, which keeps that row's
  # loaded relations: a var whose `identifier_id` the copy points at another
  # entry still holds the identifier it was saved with, and a render reads
  # that. A relation whose key the changeset changes is loaded again, at the
  # new key, with the preloads its schema declares (`Var.preloads/0`,
  # `Ref.preloads/0`), or as deep as the saved one was loaded: those of the
  # same relation and preloads in one query.
  #
  # The entry's own relations are left as they are: the form merges the ones
  # its changeset moves over the entry it casts each edit onto
  # (`rebuild_preview_relations/1` in the form), which needs them unmoved.
  defp load_moved_relations(changeset) do
    loaded =
      changeset
      |> moved_below()
      |> Enum.reject(&is_nil(elem(&1, 3)))
      |> Enum.group_by(fn {schema, name, preloads, _id} -> {schema, name, preloads} end, &elem(&1, 3))
      |> Enum.flat_map(fn {{schema, name, preloads}, ids} -> load_relations(schema, name, preloads, Enum.uniq(ids)) end)
      |> Map.new()

    put_moved_below(changeset, loaded)
  end

  defp load_relations(schema, name, preloads, ids) do
    key = schema.__schema__(:association, name).owner_key

    ids
    |> Enum.map(&Map.put(struct(schema), key, &1))
    |> Brando.Repo.preload([{name, preloads}])
    |> Enum.map(&{{schema, name, preloads, Map.get(&1, key)}, Map.get(&1, name)})
  end

  # `{schema, name, preloads, new key}` for each relation `changeset` moves
  defp moved(%Changeset{data: %schema{} = data, changes: changes}) do
    for name <- schema.__schema__(:associations),
        %Ecto.Association.BelongsTo{owner_key: key, related_key: related_key} <-
          [schema.__schema__(:association, name)],
        Map.has_key?(changes, key),
        loaded <- [Map.get(data, name)],
        not match?(%Ecto.Association.NotLoaded{}, loaded),
        (loaded && Map.get(loaded, related_key)) != changes[key],
        do: {schema, name, relation_preloads(schema, name, loaded), changes[key]}
  end

  defp moved_below(%Changeset{changes: changes}), do: changes |> Map.values() |> Enum.flat_map(&moved_tree/1)

  defp moved_tree(%Changeset{} = changeset), do: moved(changeset) ++ moved_below(changeset)
  defp moved_tree(changesets) when is_list(changesets), do: Enum.flat_map(changesets, &moved_tree/1)
  defp moved_tree(_value), do: []

  defp put_moved_below(%Changeset{changes: changes} = changeset, loaded),
    do: %{changeset | changes: Map.new(changes, fn {field, value} -> {field, put_moved(value, loaded)} end)}

  defp put_moved(%Changeset{data: data} = changeset, loaded) do
    data =
      Enum.reduce(moved(changeset), data, fn {schema, name, preloads, id}, data ->
        Map.put(data, name, id && Map.fetch!(loaded, {schema, name, preloads, id}))
      end)

    put_moved_below(%{changeset | data: data}, loaded)
  end

  defp put_moved(changesets, loaded) when is_list(changesets), do: Enum.map(changesets, &put_moved(&1, loaded))
  defp put_moved(value, _loaded), do: value

  defp relation_preloads(schema, name, loaded) do
    declared = if function_exported?(schema, :preloads, 0), do: schema.preloads(), else: []

    Enum.find_value(declared, fn
      ^name -> []
      {^name, preloads} -> preloads
      _ -> nil
    end) || loaded_shape(loaded)
  end

  # The relations `struct` has loaded, as a preload list
  defp loaded_shape(%{__meta__: _} = struct) do
    %schema{} = struct

    for name <- schema.__schema__(:associations),
        value = Map.get(struct, name),
        not match?(%Ecto.Association.NotLoaded{}, value),
        do: {name, value |> List.wrap() |> Enum.find(&is_struct/1) |> loaded_shape()}
  end

  defp loaded_shape(_value), do: []

  defp put_block_field(changeset, field, block_rows, entry, schema, user) do
    assoc =
      Enum.find(schema.__schema__(:associations), &(to_string(&1) == "entry_#{field}")) ||
        raise "Unknown block field"

    join_schema = schema.__schema__(:association, assoc).queryable
    existing = Map.get(entry, assoc) || []

    rows =
      block_rows
      |> Enum.reject(&(Modules.kept?(&1) and is_nil(saved_row(existing, &1))))
      |> Enum.map(&block_row_changeset(&1, existing, join_schema, user))

    Changeset.put_assoc(changeset, assoc, rows)
  end

  # A block `Modules.check/3` kept as it is saved stays only where the entry
  # has it: the same row, holding the same block.
  defp saved_row(existing, row) do
    Enum.find(existing, fn saved ->
      to_string(saved.id) == to_string(row["id"]) and
        (not Modules.kept?(row) or saved_block?(Map.get(saved, :block), row["block"] || row))
    end)
  end

  defp saved_block?(%{id: id, uid: uid}, params), do: to_string(id) == to_string(params["id"]) and uid == params["uid"]
  defp saved_block?(_block, _params), do: false

  defp block_row_changeset(row, existing, join_schema, user) do
    base = saved_row(existing, row) || struct(join_schema)
    row = reconcile(row, base, block_tree: true)
    row = Map.put(row, "block", put_source(row["block"], join_schema))
    join_schema.changeset(base, row, user.id, true)
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
  # In a block field's rows (`block_tree: true`) `module_id`, `block_id` and
  # `table_row_id` are owners (a var's module or block, a join row's block)
  # except on the block itself; elsewhere they can be what a row holds, such
  # as the module a module set picks.
  def reconcile(params, base, opts \\ [])

  def reconcile(params, %schema{} = base, opts) when is_map(params) do
    owners =
      if opts[:block_tree] && schema != Brando.Content.Block, do: ["module_id", "block_id", "table_row_id"], else: []

    associations = schema.__schema__(:associations)
    embeds = schema.__schema__(:embeds)
    fields = schema.__schema__(:fields) ++ schema.__schema__(:virtual_fields) ++ associations
    allowed = Enum.map(fields, &to_string/1)

    params
    |> Map.take(allowed)
    |> Map.drop(owners)
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
            reconcile_relation(value, Map.get(base, field), schema.__schema__(:association, field).queryable, opts)

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

  defp reconcile_relation(rows, current, schema, opts) when is_list(rows) do
    current = if is_list(current), do: current, else: []

    Enum.flat_map(rows, fn params ->
      base = Enum.find(current, &(Map.get(&1, :id) && to_string(&1.id) == to_string(params["id"])))

      # a block kept as it is saved (`Modules.check/3`) only where the base holds it
      if Modules.kept?(params) and not saved_block?(base, params),
        do: [],
        else: [reconcile(params, base || struct(schema), opts)]
    end)
  end

  defp reconcile_relation(params, current, schema, opts) when is_map(params) do
    base = if is_struct(current, schema), do: current, else: struct(schema)
    reconcile(params, base, opts)
  end

  defp reconcile_relation(value, _current, _schema, _opts), do: value

  # A block kept as it is saved (`Modules.check/3`) has no children in its
  # params, and gets none: an empty list would replace its saved subtree.
  defp put_source(block, source) do
    block = Map.put(block, "source", to_string(source))

    case block do
      %{"children" => children} when is_list(children) ->
        Map.put(block, "children", Enum.map(children, &put_source(&1, source)))

      _ ->
        block
    end
  end
end
