defmodule Brando.Content.Definitions.Release.Proposed do
  @moduledoc """
  The module definitions a release would give this environment, in memory:
  nothing is saved. A dry run renders with them through
  `Brando.Villain.with_modules/2` (`Brando.Content.Definitions.Release.Verify`).

  `build/1` takes a `Brando.Content.Definitions.Release.plan/1` report and
  proposes the release's version of each module it would update, and of each
  one in conflict (so a reviewer sees what the release's version does before
  choosing it). New modules are left out: no block uses them yet. Modules
  that need a migration are left out too: applying them is refused.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Definition.Params
  alias Brando.Content.{Blocks, Module, Ref, TableTemplate}
  alias Brando.Repo
  alias Ecto.Changeset

  @type t :: %{
          modules: [Module.t()],
          changed: %{integer() => Module.t()},
          uids: %{integer() => String.t()}
        }

  @proposable [:update, :conflict]

  @doc """
  The modules renders read (`Brando.Villain.render_modules/1`), with each
  proposed module in place of the stored one: `%{modules: list, changed:
  %{module_id => module}, uids: %{module_id => uid}}`.
  """
  @spec build(map()) :: t()
  def build(%{plan: plan, items: items}) do
    definitions = Map.new(plan.bundle["modules"], &{&1["uid"], &1})

    uids =
      for item <- items,
          item.kind == "module",
          item.action in @proposable,
          item.state not in [:deleted, :new],
          Map.has_key?(definitions, item.uid),
          do: item.uid

    records =
      Repo.all(from(m in Module, where: m.uid in ^uids and is_nil(m.deleted_at), preload: [:refs, :vars]))

    tables = Map.new(Repo.all(from(t in TableTemplate, select: {t.uid, t.id})))

    changed =
      Map.new(records, fn record ->
        module = propose(definitions[record.uid], record, plan.references, tables)
        {record.id, module}
      end)

    modules =
      Enum.map(Brando.Villain.render_modules(%{}), fn module ->
        case {Map.get(module, :library_origin, :local), changed[module.id]} do
          {:local, %Module{} = proposed} -> %{proposed | library_origin: module.library_origin}
          _ -> module
        end
      end)

    %{modules: modules, changed: changed, uids: Map.new(records, &{&1.id, &1.uid})}
  end

  defp propose(definition, record, references, tables) do
    creator = %Brando.Users.User{id: 0}

    definition
    |> Params.changeset(record, references, creator, tables, record.parent_id)
    |> Changeset.apply_changes()
    |> then(fn module ->
      refs = Repo.preload(module.refs, Ref.preloads(), force: true)
      vars = Enum.sort_by(module.vars, &{&1.sequence || 0, &1.key})
      %{module | refs: refs, vars: vars}
    end)
  end

  @doc """
  `entry_blocks` (an entry's blocks, as `Brando.Villain.parse/3` takes them)
  with every block of a proposed module synced to it, as applying it would
  (`Brando.Content.Blocks.sync_module/2`): a var or ref the release adds gets
  its default. In memory.
  """
  def sync_entry_blocks(entry_blocks, %{changed: changed}) when map_size(changed) == 0, do: entry_blocks

  def sync_entry_blocks(entry_blocks, proposed) when is_list(entry_blocks),
    do: Enum.map(entry_blocks, &sync_entry_block(&1, proposed))

  def sync_entry_blocks(other, _proposed), do: other

  defp sync_entry_block(%{block: %{} = block} = entry_block, proposed),
    do: %{entry_block | block: sync_block(block, proposed)}

  defp sync_entry_block(other, _proposed), do: other

  @doc "`block` and its children, each one using a proposed module synced to it."
  def sync_block(%{} = block, %{changed: changed} = proposed) do
    block =
      case changed[Map.get(block, :module_id)] do
        %Module{} = module when is_list(block.refs) and is_list(block.vars) ->
          if Map.get(block, :module_origin, :local) in [:local, nil, "local"],
            do: block |> Blocks.sync_module(module) |> Changeset.apply_changes(),
            else: block

        _ ->
          block
      end

    case Map.get(block, :children) do
      children when is_list(children) -> %{block | children: Enum.map(children, &sync_block(&1, proposed))}
      _ -> block
    end
  end

  def sync_block(block, _proposed), do: block
end
