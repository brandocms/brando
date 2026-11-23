defmodule Brando.Content.Definition.Baselines do
  @moduledoc false
  # Each environment's own record of the definitions applied to it from files
  # (`Brando.Content.DefinitionApply`): read when planning against the
  # database's baseline, written in the transaction that applies a plan.

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Definition.{Model, References, Snapshot, Value}
  alias Brando.Content.DefinitionApply
  alias Brando.Repo

  @doc "The latest row per definition, `%{{kind, uid} => row}`, with `applied_by` loaded."
  def latest do
    from(a in DefinitionApply,
      distinct: [a.kind, a.uid],
      order_by: [asc: a.kind, asc: a.uid, desc: a.id],
      preload: [:applied_by]
    )
    |> Repo.all()
    |> respelled()
    |> Map.new(&{{&1.kind, &1.uid}, &1})
  end

  # A row written before palettes were named by uid names one by id
  # (`"palette:12"`): its definition is spelled, and its digest taken again,
  # with the uid of that palette here, as a plan spells it today
  defp respelled(rows) do
    ids = for row <- rows, id <- palette_ids(row.definition), uniq: true, do: id

    uids =
      if ids == [],
        do: %{},
        else:
          Repo.all(
            from(p in Brando.Content.Palette,
              where: p.id in ^ids and is_nil(p.deleted_at) and not is_nil(p.uid),
              select: {p.id, p.uid}
            )
          )
          |> Map.new()

    if uids == %{} do
      rows
    else
      Enum.map(rows, fn row ->
        if Enum.any?(palette_ids(row.definition), &is_map_key(uids, &1)) do
          definition = respell(row.definition, uids)
          %{row | definition: definition, digest: digest(definition, %{})}
        else
          row
        end
      end)
    end
  end

  defp palette_ids(definition) do
    for var <- (definition || %{})["vars"] || [],
        %{"id" => id} <- [References.canonical_binding(get_in(var, ["assets", "palette"]), "palette")],
        do: id
  end

  defp respell(definition, uids) do
    Map.update!(definition, "vars", fn vars ->
      Enum.map(vars, fn var ->
        update_in(var, ["assets", "palette"], fn token ->
          case References.canonical_binding(token, "palette") do
            %{"id" => id} when is_map_key(uids, id) -> "palette@" <> uids[id]
            _ -> token
          end
        end)
      end)
    end)
  end

  @doc """
  The destination record IDs earlier applies bound `bundle`'s tokens to, as a
  `references` mapping (`%{token => id}`). Tokens the bundle doesn't declare,
  or declares as another kind, are left out.
  """
  def bindings(latest, bundle) do
    declared = References.declared(bundle)

    latest
    |> Map.values()
    |> Enum.sort_by(& &1.id)
    |> Enum.flat_map(&Map.to_list(&1.references || %{}))
    # A palette bound by uid is found by it again
    |> Enum.filter(fn {token, binding} ->
      declared[token] == binding["kind"] and Map.has_key?(binding, "id")
    end)
    |> Map.new(fn {token, binding} -> {token, binding["id"]} end)
  end

  @doc """
  The digest an apply row records for `definition`: a current baseline digest
  (version 2) of it with its tokens resolved through `bindings`, so renaming
  a token, or two definitions binding one record under different names,
  changes nothing.
  """
  def digest(definition, bindings), do: definition |> References.canonical(bindings) |> Snapshot.digest()

  @doc """
  The rows an apply writes, in its transaction: one per definition it wrote,
  and one per definition it found equal to the files with no row saying so
  yet (an adoption).

  `changes` are the importer's persisted changes; `items` the plan's items;
  `snapshots` the definitions as they were before the apply, by kind and
  UID. Options:
  `:source`, `:release`, `:batch_id`, `:action` (for every row it writes, in
  place of what the plan says) and `adopt: false` (no adoptions). Returns how
  many rows it wrote.
  """
  def record!(plan, changes, snapshots, actor, opts) do
    latest = latest()
    definitions = Map.new(Model.definitions(plan.bundle), &{&1["uid"], &1})
    written = MapSet.new(changes, & &1.uid)
    now = DateTime.utc_now()

    base = %{
      source: Keyword.get(opts, :source, :import),
      release: Keyword.get(opts, :release),
      batch_id: Keyword.get_lazy(opts, :batch_id, &Ecto.UUID.generate/0),
      applied_by_id: user_id(actor),
      applied_at: now
    }

    rows =
      Enum.flat_map(plan.items, fn item ->
        definition = definitions[item.uid]
        digest = digest(definition, plan.references)
        row = latest[{item.kind, item.uid}]

        cond do
          MapSet.member?(written, item.uid) ->
            action = Keyword.get(opts, :action) || action(item)
            [row(base, item, definition, digest, snapshots[{item.kind, item.uid}], action, plan)]

          Keyword.get(opts, :adopt, true) and item.state == :in_sync and
              stale?(row, digest, references(definition, plan)) ->
            [row(base, item, definition, digest, nil, :adopted, plan)]

          true ->
            []
        end
      end)

    if rows != [], do: Repo.insert_all(DefinitionApply, rows)
    length(rows)
  end

  @doc """
  Records the definitions of `plan` that equal the files, with no row saying
  so yet, as applied (`:adopted`), outside any apply. Returns how many rows it
  wrote. Two nodes booting at once write them once: the second finds the
  first's rows.
  """
  def adopt!(plan, opts) do
    items = Enum.filter(plan.items, &(&1.state == :in_sync))

    if items == [] do
      0
    else
      {:ok, count} =
        Repo.transaction(fn ->
          lock!()
          record!(%{plan | items: still_equal(plan, items)}, [], %{}, :system, opts)
        end)

      count
    end
  end

  # Planned without a lock: only what still equals the files as they were
  # planned is recorded
  # No row says so yet, or it names other tokens for the same records (the
  # files renamed one): the next plan binds the files' tokens from it
  defp stale?(nil, _digest, _references), do: true
  defp stale?(row, digest, references), do: row.digest != digest or (row.references || %{}) != references

  defp references(definition, plan) do
    Map.take(plan.references, Map.keys(References.declared(%{Model.bundle_key(definition["kind"]) => [definition]})))
  end

  defp still_equal(plan, items) do
    {snapshot, _records} = Snapshot.take!(bindings: plan.snapshot_bindings, all_tables: true)
    current = Map.new(Model.definitions(snapshot), &{{&1["kind"], &1["uid"]}, &1})
    Enum.filter(items, &(current[{&1.kind, &1.uid}] && current_digest(plan, current[{&1.kind, &1.uid}]) == &1.after))
  end

  defp current_digest(%{mode: :database} = plan, definition), do: digest(definition, plan.snapshot_bindings)
  defp current_digest(_plan, definition), do: Value.digest(definition)

  defp lock! do
    prefix = Brando.Tenant.current_prefix() || "public"

    Ecto.Adapters.SQL.query!(
      Repo.repo(),
      ~s(LOCK TABLE "#{prefix}"."content_definition_applies" IN SHARE ROW EXCLUSIVE MODE),
      []
    )
  end

  defp action(%{action: :create}), do: :created
  defp action(%{baseline: baseline}) when baseline in [:replaced, :discarded], do: :replaced
  defp action(_item), do: :updated

  defp row(base, item, definition, digest, previous, action, plan) do
    Map.merge(base, %{
      kind: item.kind,
      uid: item.uid,
      digest: digest,
      previous_digest: previous && digest(previous, plan.snapshot_bindings),
      # Its tokens written as the records they name (`"image:42"`), so a
      # revert can apply it again without the bindings of this plan
      previous: previous && References.canonical(previous, plan.snapshot_bindings),
      definition: References.canonical(definition, plan.references),
      action: action,
      references: references(definition, plan)
    })
  end

  defp user_id(%{id: id}), do: id
  defp user_id(_), do: nil
end
