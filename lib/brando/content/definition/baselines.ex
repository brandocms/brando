defmodule Brando.Content.Definition.Baselines do
  @moduledoc false
  # Each environment's own record of the definitions applied to it from files
  # (`Brando.Content.DefinitionApply`): read when planning against the
  # database's baseline, written in the transaction that applies a plan.

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Definition.{References, Snapshot, Value}
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
    |> Map.new(&{{&1.kind, &1.uid}, &1})
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
    |> Enum.filter(fn {token, binding} -> declared[token] && declared[token] == binding["kind"] end)
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
  `snapshots` the definitions as they were before the apply, by UID. Returns
  how many rows it wrote.
  """
  def record!(plan, changes, snapshots, actor, opts) do
    latest = latest()
    definitions = Map.new(plan.bundle["modules"] ++ plan.bundle["table_templates"], &{&1["uid"], &1})
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
            [row(base, item, definition, digest, snapshots[item.uid], action(item), plan)]

          item.state == :in_sync and stale?(row, digest, references(definition, plan)) ->
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
    key = if definition["kind"] == "module", do: "modules", else: "table_templates"
    Map.take(plan.references, Map.keys(References.declared(%{key => [definition]})))
  end

  defp still_equal(plan, items) do
    {snapshot, _records} = Snapshot.take!(bindings: plan.snapshot_bindings, all_tables: true)
    current = Map.new(snapshot["modules"] ++ snapshot["table_templates"], &{&1["uid"], &1})
    Enum.filter(items, &(current[&1.uid] && current_digest(plan, current[&1.uid]) == &1.after))
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
  defp action(%{baseline: :replaced}), do: :replaced
  defp action(_item), do: :updated

  defp row(base, item, definition, digest, previous, action, plan) do
    Map.merge(base, %{
      kind: item.kind,
      uid: item.uid,
      digest: digest,
      previous_digest: previous && digest(previous, plan.snapshot_bindings),
      previous: previous,
      action: action,
      references: references(definition, plan)
    })
  end

  defp user_id(%{id: id}), do: id
  defp user_id(_), do: nil
end
