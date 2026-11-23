defmodule Brando.Content.Definition.Plan do
  @moduledoc """
  A tenant-bound import plan. Apply always verifies its target state again.

  `mode` is the baseline it compares with: `:lockfile` (the bundle's own,
  from the database it was last imported into) or `:database` (the
  definitions last applied here, `Brando.Content.DefinitionApply`).
  `selection` is nil for every definition, or the UIDs an apply writes (whole
  module trees); `replace` the never-applied definitions it may replace;
  `discard` the definitions edited here since they were applied, whose edit
  it may replace with the files' version. `catch_up` compares a definition
  whose lockfile baseline is behind the last apply recorded here with that
  apply (`Brando.Content.Definition.Watcher`, whose lockfile write can fail).

  Each item has the definition's `action`, `reason`, `state` (`:new`,
  `:in_sync`, `:changed_in_release`, `:changed_in_admin`, `:changed_in_both`,
  `:never_applied` or `:deleted`), the `baseline` it was compared with
  (`:applied`, `:lockfile`, `:replaced`, `:discarded` or nil), its `ModuleDiff` `class`,
  the last apply (`applied`) and admin edit (`edited`) when known, changed
  `fields` and their `diff`, the affected `block_count` and `entry_count`,
  and for an update that removes refs or vars, `removes`: their `keys`
  (`{:ref | :var, key}`) and how many `blocks` hold one of them, in how
  many `entries`. Those blocks keep what they hold as a leftover until it is
  resolved (`Brando.Content.StaleBlocks`). For a palette's update that
  removes colours, `keys` are `{:color, key}` and `blocks` those that use
  the palette: CSS that reads a removed colour is the author's to change.

  For a module update that carries out renames its file declares
  (`Brando.Content.Definition.Renames`), `moves`: the `renames` (each with
  how many `blocks` and `entries` hold its source), the `blocks`, the
  `entries` and how many of them keep no revisions (`unrevisioned`), and
  what is `refused` (a refusal makes the item `:migration_required`). What a
  rename moves is not in `removes`. `remaps` are the declared renames the
  update leaves to a resolve, each with `ok?`: whether `resolve --map`
  would move them after the apply.

  `kind` is `"module"`, `"table_template"`, `"palette"` or `"container"`.
  """
  alias Brando.Tenant

  defstruct [
    :bundle,
    :scope,
    :fingerprint,
    :creator_id,
    mode: :lockfile,
    catch_up: false,
    selection: nil,
    replace: MapSet.new(),
    discard: MapSet.new(),
    snapshot_bindings: %{},
    items: [],
    references: %{}
  ]

  @type t :: %__MODULE__{}

  @doc "Whether every selected item is a create, update or no-op."
  def applicable?(%__MODULE__{items: items} = plan),
    do: Enum.all?(items, &(not selected?(plan, &1) or &1.action in [:create, :update, :noop]))

  @doc "Whether an apply of `plan` writes `item` (when it changes)."
  def selected?(%__MODULE__{selection: nil}, _item), do: true
  def selected?(%__MODULE__{selection: selection}, item), do: MapSet.member?(selection, item.uid)

  @doc """
  What an update removes and how many of the module's blocks hold it, as
  the plan prints it, or nil when it removes nothing.
  """
  def removal_text(%{kind: "palette", removes: %{keys: keys, blocks: blocks, entries: entries}}) do
    what = Enum.map_join(keys, ", ", fn {:color, key} -> "color #{key}" end)
    "removes #{what} (#{blocks} blocks use the palette, #{entries} entries)"
  end

  def removal_text(%{removes: %{keys: keys, blocks: blocks, entries: entries}, block_count: total}) do
    what = Enum.map_join(keys, ", ", fn {kind, key} -> "#{kind} #{key}" end)
    it = if length(keys) == 1, do: "it", else: "them"

    held =
      case {blocks, entries} do
        {0, _} -> "none of #{total} blocks hold #{it}"
        {_, 1} -> "#{blocks} of #{total} blocks hold #{it}, 1 entry"
        _ -> "#{blocks} of #{total} blocks hold #{it}, #{entries} entries"
      end

    "removes #{what} (#{held})"
  end

  def removal_text(_item), do: nil

  @doc """
  What an update moves under renamed keys, as the plan prints it, or nil:
  `moves var title → heading in 12 blocks (8 entries)`.
  """
  def move_text(%{action: :update, moves: %{renames: [_ | _] = renames}}) do
    "moves " <>
      Enum.map_join(renames, ", ", fn rename ->
        "#{rename.kind} #{rename.from} → #{rename.to} in #{count(rename.blocks, "block")} (#{count(rename.entries, "entry", "entries")})"
      end)
  end

  def move_text(_item), do: nil

  @doc "An update's `move_text/1` and `removal_text/1`, joined, or nil when it has neither."
  def changes_text(item) do
    case Enum.reject([move_text(item), removal_text(item)], &is_nil/1) do
      [] -> nil
      texts -> Enum.join(texts, "; ")
    end
  end

  defp count(count, one, many \\ nil)
  defp count(1, one, _many), do: "1 #{one}"
  defp count(count, one, many), do: "#{count} #{many || one <> "s"}"

  @doc """
  The `mix brando.modules resolve` command that clears what an update of
  `plan` leaves in blocks, as it runs in the current environment: it drops
  each removed key blocks hold, and moves each one the files rename
  (`remaps`) onto its new key. Nil when no block holds one, when the plan
  has no user to name, or when a dry run of a move refuses something
  (resolve those under Resolve blocks). Each value is quoted for a POSIX
  shell.
  """
  def resolve_command(%__MODULE__{creator_id: user_id}, %{kind: "module", uid: uid} = item)
      when not is_nil(user_id) do
    remaps = Map.get(item, :remaps, [])
    mapped = MapSet.new(remaps, &{&1.kind, &1.from})
    held = for held <- held(item), not MapSet.member?(mapped, held), do: held

    if (held != [] or remaps != []) and Enum.all?(remaps, & &1.ok?) do
      drops = Enum.flat_map(held, fn {kind, key} -> ["--drop", "#{kind}:#{key}"] end)
      resolve_command(uid, user_id, drops, remaps)
    end
  end

  def resolve_command(_plan, _item), do: nil

  @doc """
  The `mix brando.modules resolve --apply` command that runs `drops`
  (`--drop` arguments) and moves the values of `renames` (`--map`) in the
  blocks of the module `uid`, as the user `user_id` (the placeholder
  `USER_ID` when nil) in the current environment. Each value is quoted for
  a POSIX shell.
  """
  def resolve_command(uid, user_id, drops, renames) do
    environment =
      if Tenant.enabled?(),
        do: ["--site", Tenant.current_site_key(), "--environment", Tenant.current_environment_key()],
        else: []

    maps = Enum.flat_map(renames, &["--map", "#{&1.kind}:#{&1.from}=#{&1.to}"])

    (~w(mix brando.modules resolve --uid) ++
       [uid, "--user", to_string(user_id || "USER_ID")] ++ environment ++ drops ++ maps ++ ["--apply"])
    |> Enum.map_join(" ", &shell_quote/1)
  end

  defp held(%{removes: %{held: held, blocks: blocks}}) when blocks > 0, do: held
  defp held(_item), do: []

  @doc """
  The line that follows an update whose removed or renamed keys blocks
  hold: the `resolve_command/2`, or where to resolve them. Nil when no block
  holds them.
  """
  def resolve_line(plan, item) do
    if match?(%{removes: %{blocks: blocks}} when blocks > 0, item) or Map.get(item, :remaps, []) != [] do
      case resolve_command(plan, item) do
        nil ->
          "resolve: after the apply, under Resolve blocks on the module in the admin, or with mix brando.modules resolve"

        command ->
          "resolve: " <> command
      end
    end
  end

  defp shell_quote(value) do
    if value =~ ~r/\A[A-Za-z0-9_@%+=:,.\/-]+\z/,
      do: value,
      else: "'" <> String.replace(value, "'", ~S('\'')) <> "'"
  end
end
