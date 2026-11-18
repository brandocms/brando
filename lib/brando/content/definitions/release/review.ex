defmodule Brando.Content.Definitions.Release.Review do
  @moduledoc """
  What the admin's Release changes screen shows of a release plan
  (`Brando.Content.Definitions.Release.plan/1`): one row per module tree
  (a module with its children and the table templates it uses), the
  structured differences of each definition, and the three versions of a
  definition in conflict.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Definition.Baselines
  alias Brando.Content.DefinitionApply
  alias Brando.Repo

  @class_order [:metadata, :render, :compatible, :destructive]
  @metadata ~w(name namespace help_text class type color svg multi datasource datasource_module datasource_type datasource_query write_with_ai table_template)

  @type row :: %{
          uid: String.t(),
          kind: String.t(),
          namespace: String.t() | nil,
          title: String.t(),
          items: [map()],
          children: [String.t()],
          group: :choice | :ready | :blocked,
          status: :update | :create | :conflict | :never_applied | :blocked | :deleted,
          class: atom() | nil,
          note: String.t() | nil,
          uids: [String.t()]
        }

  @doc """
  The plan's changes as rows, one per module tree, in the order the screen
  lists them: those that need a choice, those ready to apply, those that
  can't be applied yet. A table template goes with the first tree that uses
  it, or has a row of its own.
  """
  @spec rows(map()) :: [row()]
  def rows(%{plan: plan, items: items}) do
    bundle = plan.bundle
    modules = Map.new(bundle["modules"], &{&1["uid"], &1})
    tables = Map.new(bundle["table_templates"], &{&1["uid"], &1})
    parents = for module <- bundle["modules"], child <- module["children"], into: %{}, do: {child, module["uid"]}
    pending = Enum.reject(items, &(&1.action == :noop))

    pending
    |> Enum.group_by(&tree(&1, parents, modules))
    |> Enum.map(fn {root, tree_items} -> row(root, tree_items, modules, tables) end)
    |> Enum.sort_by(&{group_rank(&1.group), &1.namespace || "", &1.title})
  end

  defp tree(%{kind: "module", uid: uid}, parents, _modules), do: root(uid, parents)

  defp tree(%{kind: "table_template", uid: uid}, parents, modules) do
    case Enum.find(Map.values(modules), &(&1["table_template"] == uid)) do
      nil -> uid
      module -> root(module["uid"], parents)
    end
  end

  defp root(uid, parents), do: if(parent = parents[uid], do: root(parent, parents), else: uid)

  defp row(root, items, modules, tables) do
    definition = modules[root] || tables[root]
    language = language()
    root_item = Enum.find(items, &(&1.uid == root))
    others = Enum.reject(items, &(&1.uid == root))

    {group, status, note} = status(items)

    %{
      uid: root,
      kind: definition["kind"],
      namespace: text(definition["namespace"], language),
      title: text(definition["name"], language) || root,
      items: Enum.sort_by(items, &(&1.uid != root)),
      root_item: root_item,
      children: Enum.map(others, &text((modules[&1.uid] || tables[&1.uid])["name"], language)),
      group: group,
      status: status,
      class: worst_class(items),
      note: note,
      uids: Enum.map(items, & &1.uid),
      entry_count: items |> Enum.map(& &1.entry_count) |> Enum.max(fn -> 0 end)
    }
  end

  defp status(items) do
    cond do
      blocked = Enum.find(items, &(&1.action == :migration_required)) -> {:blocked, :blocked, blocked.reason}
      deleted = Enum.find(items, &(&1.state == :deleted)) -> {:blocked, :deleted, deleted.reason}
      Enum.any?(items, &(&1.state == :never_applied)) -> {:choice, :never_applied, nil}
      Enum.any?(items, &(&1.action == :conflict)) -> {:choice, :conflict, nil}
      Enum.all?(items, &(&1.action == :create)) -> {:ready, :create, nil}
      true -> {:ready, :update, nil}
    end
  end

  defp group_rank(:choice), do: 0
  defp group_rank(:ready), do: 1
  defp group_rank(:blocked), do: 2

  defp worst_class(items) do
    items
    |> Enum.map(& &1.class)
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&(Enum.find_index(@class_order, fn class -> class == &1 end) || 99), fn -> nil end)
    |> then(fn class ->
      if Enum.any?(items, &(&1.action == :migration_required)), do: :migration_required, else: class
    end)
  end

  @doc """
  Counts for the summary: by action (`update`, `new`, `conflict`,
  `never_applied`, `migration_required`) and by class, over rows.
  """
  def counts(rows) do
    %{
      actions: %{
        update: Enum.count(rows, &(&1.status == :update)),
        new: Enum.count(rows, &(&1.status == :create)),
        conflict: Enum.count(rows, &(&1.status in [:conflict, :deleted])),
        never_applied: Enum.count(rows, &(&1.status == :never_applied)),
        migration_required: Enum.count(rows, &(&1.status == :blocked))
      },
      classes:
        Map.new(@class_order ++ [:migration_required], fn class -> {class, Enum.count(rows, &(&1.class == class))} end)
    }
  end

  @doc """
  The definition of `uid` in the release's files and as it is here, both as
  canonical maps (`nil` when it isn't there).
  """
  def definitions(%{plan: plan}, uid) do
    release = Enum.find(plan.bundle["modules"] ++ plan.bundle["table_templates"], &(&1["uid"] == uid))
    {here, _records} = Brando.Content.Definition.Snapshot.take!(all_tables: true)
    current = Enum.find(here["modules"] ++ here["table_templates"], &(&1["uid"] == uid))
    %{release: release, here: current, applied: applied(uid)}
  end

  # The definition as last applied here (or found equal to the files),
  # whose `definition` the row holds from brando_232 on
  defp applied(uid) do
    Repo.one(
      from(a in DefinitionApply,
        where: a.uid == ^uid,
        order_by: [desc: a.id],
        limit: 1,
        preload: [:applied_by]
      )
    )
  end

  @doc """
  A definition as lines of text for a diff: its fields, then its refs and
  vars, then its template. Nil for nil.
  """
  def definition_text(nil), do: nil

  def definition_text(definition) do
    language = language()

    fields =
      @metadata
      |> Enum.map(&{&1, definition[&1]})
      |> Enum.reject(fn {_field, value} -> value in [nil, "", false] or value == %{} end)
      |> Enum.map(fn {field, value} -> "#{field}: #{inline(value, language)}" end)

    refs = for ref <- definition["refs"] || [], do: "ref #{ref["name"]} (#{type(ref)})#{described(ref["description"])}"

    vars =
      for var <- definition["vars"] || [],
          do: "var #{var["key"]} (#{var["type"]})#{described(text(var["label"], language))}#{default(var["value"])}"

    code = if definition["code"], do: ["", "template:" | String.split(definition["code"], ~r/\r\n|\n|\r/)], else: []
    Enum.join(fields ++ refs ++ vars ++ code, "\n")
  end

  defp inline(%{} = map, language), do: text(map, language) |> inline(language)
  defp inline(value, _language) when is_binary(value), do: String.replace(value, ~r/\s+/, " ")
  defp inline(value, _language), do: inspect(value)

  defp described(nil), do: ""
  defp described(""), do: ""
  defp described(text), do: " “#{text}”"

  defp default(nil), do: ""
  defp default(""), do: ""
  defp default(value), do: ", default #{inspect(value)}"

  @doc """
  The structured differences of a definition, here → release: its fields
  (`metadata`), refs and vars, each `%{key, label, change, before, after}`
  with `change` `:added`, `:removed`, `:changed` or `:same`.
  """
  def structure(here, release) do
    %{
      metadata: metadata(here || %{}, release || %{}),
      refs: by_key(here["refs"] || [], (release || %{})["refs"] || [], "name"),
      vars: by_key(here["vars"] || [], (release || %{})["vars"] || [], "key")
    }
  end

  defp metadata(here, release) do
    for field <- @metadata, Map.get(here, field) != Map.get(release, field) do
      %{key: field, change: :changed, before: Map.get(here, field), after: Map.get(release, field)}
    end
  end

  defp by_key(before, after_list, key) do
    before_map = Map.new(before, &{&1[key], &1})
    after_map = Map.new(after_list, &{&1[key], &1})
    keys = Enum.uniq(Enum.map(before, & &1[key]) ++ Enum.map(after_list, & &1[key]))

    Enum.map(keys, fn name ->
      {b, a} = {before_map[name], after_map[name]}

      change =
        cond do
          is_nil(b) -> :added
          is_nil(a) -> :removed
          comparable(b) == comparable(a) -> :same
          true -> :changed
        end

      %{
        key: name,
        change: change,
        type: type(a || b),
        before: b,
        after: a,
        fields: if(change == :changed, do: changed_fields(b, a), else: [])
      }
    end)
  end

  defp comparable(map), do: Map.drop(map, ["sequence", "uid", "assets"])

  defp changed_fields(b, a),
    do:
      (Map.keys(b) ++ Map.keys(a))
      |> Enum.uniq()
      |> Enum.reject(&(&1 in ~w(sequence uid)))
      |> Enum.filter(&(b[&1] != a[&1]))

  defp type(%{"type" => type}) when is_binary(type), do: type
  defp type(%{"data" => %{"type" => type}}), do: type
  defp type(_), do: nil

  @doc """
  Three versions of a template, line by line: `base` (as last applied),
  `ours` (as edited here) and `theirs` (the release's), aligned on `base`.
  Returns hunks with a line of context, each `%{from, to, where, rows}`, a
  row `%{base, ours, theirs}` of `{class, line}` cells. `where` is `:both`,
  `:here` or `:release`.
  """
  def three_way(base, ours, theirs) do
    base_lines = lines(base)
    ours_side = align(base_lines, lines(ours))
    theirs_side = align(base_lines, lines(theirs))

    rows =
      Enum.flat_map(0..length(base_lines), fn index ->
        inserted(index, ours_side, theirs_side) ++ base_row(index, base_lines, ours_side, theirs_side)
      end)

    hunks(rows)
  end

  defp lines(nil), do: []
  defp lines(text), do: String.split(text, ~r/\r\n|\n|\r/)

  # For each base line: whether the other side keeps it, and the lines the
  # other side inserts before each base position
  defp align(base, other) do
    {kept, inserts, _position} =
      base
      |> List.myers_difference(other)
      |> Enum.reduce({%{}, %{}, 0}, fn
        {:eq, lines}, {kept, inserts, at} ->
          kept = Enum.reduce(Enum.with_index(lines, at), kept, fn {_line, i}, kept -> Map.put(kept, i, true) end)
          {kept, inserts, at + length(lines)}

        {:del, lines}, {kept, inserts, at} ->
          kept = Enum.reduce(Enum.with_index(lines, at), kept, fn {_line, i}, kept -> Map.put(kept, i, false) end)
          {kept, inserts, at + length(lines)}

        {:ins, lines}, {kept, inserts, at} ->
          {kept, Map.update(inserts, at, lines, &(&1 ++ lines)), at}
      end)

    %{kept: kept, inserts: inserts}
  end

  # A base line one side dropped and replaced with lines inserted right
  # after it shows the first of them beside it
  defp base_row(index, base, ours, theirs) do
    case Enum.at(base, index) do
      nil -> []
      line -> base_row_for(index, line, ours, theirs)
    end
  end

  defp base_row_for(index, line, ours, theirs) do
    {ours_cell, ours_changed?} = side_cell(ours, index, line)
    {theirs_cell, theirs_changed?} = side_cell(theirs, index, line)
    base_class = if ours_changed? or theirs_changed?, do: "is-base-changed"

    [%{base: {base_class, line}, ours: ours_cell, theirs: theirs_cell, changed: changed(ours_changed?, theirs_changed?)}]
  end

  defp side_cell(side, index, line) do
    if side.kept[index] do
      {{nil, line}, false}
    else
      case side.inserts[index + 1] do
        [replacement | _] -> {{:replaced, replacement}, true}
        _ -> {{"is-empty", nil}, true}
      end
    end
  end

  defp inserted(index, ours, theirs) do
    ours_lines = insert_lines(ours, index)
    theirs_lines = insert_lines(theirs, index)
    count = max(length(ours_lines), length(theirs_lines))

    if count == 0 do
      []
    else
      for i <- 0..(count - 1) do
        ours_line = Enum.at(ours_lines, i)
        theirs_line = Enum.at(theirs_lines, i)

        %{
          base: {"is-empty", nil},
          ours: if(ours_line, do: {"is-ours", ours_line}, else: {"is-empty", nil}),
          theirs: if(theirs_line, do: {"is-theirs", theirs_line}, else: {"is-empty", nil}),
          changed: changed(not is_nil(ours_line), not is_nil(theirs_line))
        }
      end
    end
  end

  # The lines a side inserts at `index`, without the one shown beside the
  # base line it replaced
  defp insert_lines(side, index) do
    lines = side.inserts[index] || []
    if index > 0 and side.kept[index - 1] == false and lines != [], do: tl(lines), else: lines
  end

  defp changed(true, true), do: :both
  defp changed(true, false), do: :here
  defp changed(false, true), do: :release
  defp changed(false, false), do: nil

  defp hunks(rows) do
    rows = Enum.map(rows, &%{&1 | ours: replaced(&1.ours, "is-ours"), theirs: replaced(&1.theirs, "is-theirs")})
    changed = for {%{changed: side}, i} <- Enum.with_index(rows, 1), side, do: i

    changed
    |> Enum.chunk_while([], &close_group/2, &last_group/1)
    |> Enum.map(&hunk(&1, rows))
  end

  # Changes three lines or less apart share a hunk; groups are kept reversed
  defp close_group(i, []), do: {:cont, [i]}
  defp close_group(i, [last | _] = acc) when i - last <= 3, do: {:cont, [i | acc]}
  defp close_group(i, acc), do: {:cont, Enum.reverse(acc), [i]}

  defp last_group([]), do: {:cont, []}
  defp last_group(acc), do: {:cont, Enum.reverse(acc), []}

  defp hunk([first | _] = group, rows) do
    from = max(first - 1, 1)
    to = min(Enum.max(group) + 1, length(rows))
    hunk_rows = Enum.slice(rows, (from - 1)..(to - 1))
    sides = hunk_rows |> Enum.map(& &1.changed) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    %{from: from, to: to, where: where(sides), rows: hunk_rows}
  end

  defp where(sides) do
    cond do
      :both in sides or (:here in sides and :release in sides) -> :both
      sides == [:here] -> :here
      true -> :release
    end
  end

  defp replaced({:replaced, line}, class), do: {class, line}
  defp replaced(cell, _class), do: cell

  @doc "Whether an apply row's definition equals `definition` as resolved here."
  def same?(%DefinitionApply{digest: digest}, definition, bindings), do: Baselines.digest(definition, bindings) == digest

  defp language, do: to_string(Brando.config(:default_admin_language) || "en")

  @doc false
  def text(%{} = map, language), do: map[language] || map["en"] || map |> Map.values() |> List.first()
  def text(value, _language), do: value
end
