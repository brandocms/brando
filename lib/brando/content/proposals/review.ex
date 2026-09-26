defmodule Brando.Content.Proposals.Review do
  use Gettext, backend: Brando.Gettext

  @moduledoc """
  What a reviewer sees of a proposal: one card per destination entry, in the
  order the operations name them, with each change described.

  Everything here is derived from the stored proposal — the same frozen
  operations `apply/3` executes — so the review cannot drift from the result.
  """
  alias Brando.Content

  alias Brando.Content.Proposals.{
    BlockTree,
    CopyBlock,
    CreateEntry,
    DeleteBlock,
    InsertBlock,
    MoveBlock,
    Proposal,
    SetBlockActive,
    SetBlockDetails,
    SetBlockMedia,
    SetBlockSelection,
    SetBlockTable,
    SetBlockText,
    SetBlockValues,
    SetFields,
    SetRefConfig
  }

  alias Brando.Content.Proposals.EntryFields
  alias Brando.Content.Proposals.RefConfig

  alias Brando.Content.Transfer.Catalog

  @excerpt 90

  @doc "Review cards for `proposal`."
  @spec entries(Proposal.t()) :: [map()]
  def entries(%Proposal{} = proposal) do
    proposal.targets
    |> Enum.sort_by(fn {target, _} -> first_mention(proposal, target) end)
    |> Enum.map(fn {target, value} -> entry(target, value, proposal) end)
  end

  @doc """
  Every `{kind, id}` media reference in the review cards, for batch loading:
  the media a proposal places, and the `context` media that identify the
  blocks it changes, moves or removes.
  """
  @spec media([map()]) :: [{:image | :video, integer()}]
  def media(entries) do
    context =
      for entry <- entries,
          change <- entry.changes,
          %{kind: kind, id: id} <- (change[:context] || []) ++ (change[:replaces] || []),
          do: {kind, id}

    values =
      for entry <- entries,
          %{values: values} <- entry.changes,
          is_list(values),
          %{media: %{kind: kind, id: id}} <- values,
          do: {kind, id}

    context = context ++ values
    entries |> Enum.flat_map(& &1.media) |> Enum.concat(context) |> Enum.uniq()
  end

  defp entry({:new, ref} = target, schema, proposal) do
    %CreateEntry{fields: fields} = Enum.find(proposal.operations, &match?(%CreateEntry{ref: ^ref}, &1))

    changes = [%{type: :create, fields: fields |> order_fields() |> Enum.map(fn {k, v} -> field_view(schema, k, v) end)}]
    changes = changes ++ block_changes(target, nil, proposal)

    %{
      key: Proposal.key(target),
      target: target,
      action: :create,
      content_type: Brando.Blueprint.get_singular(schema),
      title: fields["title"] || fields["name"] || ref,
      url: nil,
      admin_url: nil,
      status: "draft",
      live?: false,
      changes: changes,
      media: media_of(changes),
      highlight: uids_of(changes),
      preview?: Brando.LivePreview.has_live_preview_target(schema),
      preview_targets: preview_targets(schema),
      problems: problems(proposal, target)
    }
  end

  defp entry({schema, id} = target, entry, proposal) do
    changes = field_changes(target, entry, proposal) ++ block_changes(target, entry, proposal)
    described = Catalog.describe(entry)

    %{
      key: Proposal.key(target),
      target: target,
      action: :update,
      content_type: Brando.Blueprint.get_singular(schema),
      title: described.title,
      url: blank(described.url),
      admin_url: admin_url(schema, id),
      status: to_string(Map.get(entry, :status) || ""),
      live?: target in (proposal.effects[:live] || []),
      changes: changes,
      media: media_of(changes),
      highlight: uids_of(changes),
      preview?: Brando.LivePreview.has_live_preview_target(schema),
      preview_targets: preview_targets(schema),
      problems: problems(proposal, target)
    }
  end

  defp field_changes(target, entry, proposal) do
    fields =
      for %SetFields{target: ^target, fields: fields} <- proposal.operations,
          {name, value} <- fields,
          do:
            Map.put(
              field_view(entry.__struct__, name, value),
              :before,
              saved_value(entry, name)
            )

    indices = for {%SetFields{target: ^target}, index} <- Enum.with_index(proposal.operations), do: index
    if fields == [], do: [], else: [%{type: :fields, fields: fields, operations: indices}]
  end

  defp block_changes(target, entry, proposal) do
    orders = orders(target, entry, proposal)

    proposal.operations
    |> Enum.with_index()
    |> Enum.flat_map(fn
      # Moves are shown as the order they produce, once per list of siblings,
      # where the first move into that list is.
      # A copy to another entry shows in that entry's order, and as a note here.
      {%CopyBlock{target: ^target, to_target: to} = op, index} when not is_nil(to) ->
        [Map.put(copy_out(op, entry, proposal), :operations, [index])]

      {%CopyBlock{to_target: ^target}, index} ->
        Map.get(orders, index, [])

      {%{__struct__: kind, target: ^target}, index} when kind in [MoveBlock, CopyBlock] ->
        Map.get(orders, index, [])

      # Each change names the operations it comes from, so the reviewer can
      # leave it out. A new order is all or nothing: it has no operations.
      {op, index} ->
        op |> block_change(target, entry, proposal) |> Enum.map(&Map.put(&1, :operations, [index]))
    end)
  end

  defp block_change(%InsertBlock{target: target} = op, target, entry, proposal) do
    module = fetch_module(op.module)

    [
      %{
        type: :insert_block,
        uid: op.uid,
        field: op.field,
        module: module && label(module.name),
        placement: placement(op.placement, op.parent, entry, op.field, proposal),
        values: Enum.map(op.values, &value_view(&1, nil, op.uid, proposal)),
        texts: Enum.map(op.texts, fn {ref, text} -> %{ref: ref, text: excerpt(text)} end),
        media: Enum.flat_map(op.media, fn {ref, asset} -> media_items(ref, asset) end),
        settings:
          Enum.flat_map(op.configs, fn {ref, config} ->
            Enum.map(config, fn {key, value} -> %{ref: ref, name: key, before: nil, value: shorten(value)} end)
          end)
      }
    ]
  end

  defp block_change(%SetBlockMedia{target: target} = op, target, entry, proposal) do
    [
      %{
        type: :block_media,
        uid: op.block_uid,
        block: block_label(entry, op.field, op.block_uid, proposal),
        ref: to_string(op.ref),
        media: media_items(to_string(op.ref), op.asset),
        replaces: entry |> saved_block(op.field, op.block_uid) |> ref_media(to_string(op.ref))
      }
    ]
  end

  defp block_change(%SetRefConfig{target: target} = op, target, entry, proposal) do
    saved = saved_block(entry, op.field, op.block_uid)
    ref = saved && Enum.find(saved.refs, &(&1.name == op.ref))

    [
      %{
        type: :ref_config,
        uid: op.block_uid,
        block: block_label(entry, op.field, op.block_uid, proposal),
        ref: op.ref,
        settings:
          for {key, before, value} <- RefConfig.diff(ref, op.config) do
            %{name: key, before: shorten(before), value: shorten(value)}
          end,
        context: block_media(saved)
      }
    ]
  end

  defp block_change(%SetBlockDetails{target: target} = op, target, entry, proposal) do
    saved = saved_block(entry, op.field, op.block_uid)

    [
      %{
        type: :block_details,
        uid: op.block_uid,
        block: block_label(entry, op.field, op.block_uid, proposal),
        settings:
          for {key, value} <- [anchor: op.anchor, description: op.description], not is_nil(value) do
            %{name: to_string(key), before: saved && Map.get(saved, key), value: value}
          end
      }
    ]
  end

  defp block_change(%SetBlockText{target: target} = op, target, entry, proposal) do
    [
      %{
        type: :block_text,
        uid: op.block_uid,
        block: block_label(entry, op.field, op.block_uid, proposal),
        ref: to_string(op.ref),
        before: excerpt(saved_text(entry, op.field, op.block_uid, op.ref)),
        text: excerpt(op.text)
      }
    ]
  end

  defp block_change(%SetBlockActive{target: target} = op, target, entry, proposal) do
    [
      %{
        type: :block_active,
        uid: op.block_uid,
        block: block_label(entry, op.field, op.block_uid, proposal),
        ref: op.ref,
        active: op.active,
        context: block_media(saved_block(entry, op.field, op.block_uid))
      }
    ]
  end

  defp block_change(%SetBlockValues{target: target} = op, target, entry, proposal) do
    saved = saved_block(entry, op.field, op.block_uid)

    [
      %{
        type: :block_values,
        uid: op.block_uid,
        block: block_label(entry, op.field, op.block_uid, proposal),
        values: Enum.map(op.values, &value_view(&1, saved, op.block_uid, proposal)),
        context: block_media(saved)
      }
    ]
  end

  defp block_change(%DeleteBlock{target: target} = op, target, entry, proposal) do
    saved = saved_block(entry, op.field, op.block_uid)

    [
      %{
        type: :delete_block,
        uid: nil,
        block: block_label(entry, op.field, op.block_uid, proposal),
        children: descendants(saved),
        context: block_media(saved)
      }
    ]
  end

  defp block_change(%SetBlockTable{target: target} = op, target, entry, proposal) do
    saved = saved_block(entry, op.field, op.block_uid)

    [
      %{
        type: :block_table,
        uid: op.block_uid,
        block: block_label(entry, op.field, op.block_uid, proposal),
        before: saved && length(saved.table_rows || []),
        rows:
          Enum.map(op.rows, fn row ->
            row |> Enum.sort() |> Enum.map_join(" · ", fn {_key, value} -> to_string(option(nil, value) || "") end)
          end)
      }
    ]
  end

  defp block_change(%SetBlockSelection{target: target} = op, target, entry, proposal) do
    saved = saved_block(entry, op.field, op.block_uid)
    titles = identifier_titles(op.identifiers)

    [
      %{
        type: :block_selection,
        uid: op.block_uid,
        block: block_label(entry, op.field, op.block_uid, proposal),
        before:
          saved &&
            Enum.map(saved.block_identifiers || [], fn bi ->
              (bi.identifier && bi.identifier.title) || "##{bi.identifier_id}"
            end),
        entries: Enum.map(op.identifiers, &Map.get(titles, &1, "##{&1}"))
      }
    ]
  end

  defp block_change(_op, _target, _entry, _proposal), do: []

  defp identifier_titles(ids) do
    case Content.list_identifiers(ids) do
      {:ok, identifiers} -> Map.new(identifiers, &{&1.id, &1.title})
      _ -> %{}
    end
  end

  # The order cards of `target`, keyed by the index of the first move into
  # each list of siblings. The operations are replayed on the saved field, so
  # a card shows the final order, with what is new and what moved.
  defp orders(target, entry, proposal) do
    ops =
      proposal.operations
      |> Enum.with_index()
      |> Enum.flat_map(fn
        {%CopyBlock{to_target: ^target} = op, index} -> [{op.to_field, {{:copy_in, op, proposal}, index}}]
        {%CopyBlock{to_target: to}, _} when not is_nil(to) -> []
        {op, index} -> if Map.get(op, :target) == target, do: [{Map.get(op, :field), {op, index}}], else: []
      end)

    ops
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn
      {nil, _} -> []
      {field, ops} -> field_orders(field, ops, entry, proposal)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp field_orders(field, ops, entry, proposal) do
    tree = if entry, do: entry |> Map.get(:"entry_#{field}", []) |> BlockTree.from_saved(), else: %BlockTree{}

    {tree, firsts, moved} = Enum.reduce(ops, {tree, %{}, MapSet.new()}, &replay/2)

    for {parent, index} <- Enum.sort_by(firsts, &elem(&1, 1)) do
      items = Enum.map(BlockTree.children(tree, parent), &order_item(&1, entry, field, moved, proposal))

      {index,
       %{
         type: :order,
         uid: nil,
         uids: MapSet.to_list(moved),
         parent: parent && block_label(entry, field, parent, proposal),
         items: items,
         context: Enum.flat_map(items, & &1.media)
       }}
    end
  end

  # Replay one operation on the review's tree. `firsts` maps each list of
  # siblings a move touches to the first move's index; a block that changes
  # parent changes both lists.
  defp replay({%MoveBlock{} = op, index}, {tree, firsts, moved} = acc) do
    case BlockTree.fetch(tree, op.block_uid) do
      %{parent: from} ->
        to = move_parent(op.placement, from, tree)
        firsts = firsts |> Map.put_new(from, index) |> Map.put_new(to, index)
        {BlockTree.move(tree, op.block_uid, to, op.placement), firsts, MapSet.put(moved, op.block_uid)}

      nil ->
        acc
    end
  end

  # A copy is new in the list it joins.
  defp replay({%CopyBlock{} = op, index}, {tree, firsts, moved} = acc) do
    case BlockTree.fetch(tree, op.block_uid) do
      %{parent: from} ->
        to = if op.placement == :append, do: from, else: move_parent(op.placement, from, tree)
        {BlockTree.copy(tree, op.block_uid, op.uid, to, op.placement), Map.put_new(firsts, to, index), moved}

      nil ->
        acc
    end
  end

  defp replay({{:copy_in, op, proposal}, index}, {tree, firsts, moved} = acc) do
    source = proposal.targets |> Map.get(op.target) |> saved_tree(op.field)
    to = move_parent(op.placement, nil, tree)

    if BlockTree.fetch(source, op.block_uid),
      do:
        {BlockTree.copy_from(source, tree, op.block_uid, op.uid, to, op.placement), Map.put_new(firsts, to, index), moved},
      else: acc
  end

  defp replay({%DeleteBlock{} = op, _index}, {tree, firsts, moved} = acc) do
    if BlockTree.fetch(tree, op.block_uid), do: {BlockTree.delete(tree, op.block_uid), firsts, moved}, else: acc
  end

  defp replay({%InsertBlock{} = op, _index}, {tree, firsts, moved}) do
    node = %{uid: op.uid, parent: op.parent, type: :module, module: op.module, multi: false, slot_module_set: nil}
    {BlockTree.put(tree, node, op.parent, op.placement), firsts, moved}
  end

  defp replay(_op, acc), do: acc

  defp saved_tree(%{} = entry, field), do: entry |> Map.get(:"entry_#{field}", []) |> BlockTree.from_saved()
  defp saved_tree(_new, _field), do: %BlockTree{}

  defp copy_out(op, entry, proposal) do
    destination =
      case Map.get(proposal.targets, op.to_target) do
        %{} = other -> Catalog.describe(other).title
        _ -> dgettext("content_proposals", "the new entry")
      end

    %{
      type: :copy_out,
      uid: nil,
      block: block_label(entry, op.field, op.block_uid, proposal),
      destination: destination,
      context: block_media(saved_block(entry, op.field, op.block_uid))
    }
  end

  defp move_parent(:append, from, _tree), do: from
  defp move_parent({:into, parent}, _from, _tree), do: parent

  defp move_parent({_side, anchor}, from, tree) do
    case BlockTree.fetch(tree, anchor) do
      %{parent: parent} -> parent
      nil -> from
    end
  end

  defp order_item(uid, entry, field, moved, proposal) do
    # A copy shows its original.
    copy = Enum.find(proposal.operations, &match?(%CopyBlock{uid: ^uid}, &1))

    saved =
      case copy do
        %CopyBlock{to_target: to} when not is_nil(to) ->
          proposal.targets |> Map.get(copy.target) |> saved_block(copy.field, copy.block_uid)

        _ ->
          saved_block(entry, field, original(copy, uid))
      end

    inserted = Enum.find(proposal.operations, &match?(%InsertBlock{uid: ^uid}, &1))

    %{
      uid: uid,
      name: item_name(saved, inserted),
      excerpt: saved && saved |> describe() |> brief(),
      new?: is_nil(saved) or not is_nil(copy),
      copy?: not is_nil(copy),
      moved?: MapSet.member?(moved, uid),
      media: proposed_media(uid, proposal) || block_media(saved),
      values:
        select_values(if(saved, do: saved.vars, else: inserted_vars(inserted)), proposed_values(uid, inserted, proposal))
    }
  end

  # The media a block will show: the last media the proposal gives it.
  defp proposed_media(uid, proposal) do
    case proposal.operations |> Enum.filter(&match?(%SetBlockMedia{block_uid: ^uid}, &1)) |> List.last() do
      nil -> nil
      op -> op.ref |> to_string() |> media_items(op.asset) |> Enum.take(1)
    end
  end

  defp original(nil, uid), do: uid
  defp original(%CopyBlock{block_uid: original}, _uid), do: original

  defp item_name(nil, nil), do: nil
  defp item_name(nil, inserted), do: module_label(inserted.module)
  defp item_name(saved, _inserted), do: block_name(saved)

  defp select_values(vars, set) do
    for %{type: :select} = var <- vars || [] do
      value = Map.get(set, var.key, var.value)
      %{label: var.label || var.key, value: option(var, value), changed?: Map.has_key?(set, var.key)}
    end
  end

  # The values the proposal gives a block: an insert's, then later settings.
  defp proposed_values(uid, inserted, proposal) do
    for %SetBlockValues{block_uid: ^uid, values: values} <- proposal.operations,
        reduce: (inserted && inserted.values) || %{},
        do: (acc -> Map.merge(acc, values))
  end

  defp inserted_vars(nil), do: []

  defp inserted_vars(%InsertBlock{module: module}) do
    case fetch_module(module) do
      %{vars: vars} -> vars
      _ -> []
    end
  end

  # What a saved ref shows now.
  defp ref_media(nil, _name), do: []

  defp ref_media(block, name) do
    case Enum.find(block.refs, &(&1.name == name)) do
      nil -> []
      ref -> ref |> ref_items() |> Enum.map(fn {kind, id} -> %{ref: name, kind: kind, id: id} end)
    end
  end

  defp ref_items(%{gallery: %{gallery_objects: [_ | _] = objects}}),
    do: Enum.map(objects, &if(&1.video_id, do: {:video, &1.video_id}, else: {:image, &1.image_id}))

  defp ref_items(ref), do: for(kind <- [:image, :video, :file], id = Map.get(ref, :"#{kind}_id"), do: {kind, id})

  # Media as the review shows it: a gallery item by item.
  defp media_items(ref, {:gallery, items}), do: Enum.map(items, fn {kind, id} -> %{ref: ref, kind: kind, id: id} end)
  defp media_items(ref, {kind, id}), do: [%{ref: ref, kind: kind, id: id}]

  defp brief(nil), do: nil
  defp brief(text) when byte_size(text) > 48, do: String.slice(text, 0, 48) <> "…"
  defp brief(text), do: text

  # Where a new block goes, relative to a neighbour the editor recognises.
  defp placement(:append, parent, entry, field, proposal) when is_binary(parent) do
    anchor =
      case saved_block(entry, field, parent) do
        %{children: [_ | _] = children} -> block_anchor(List.last(children))
        _ -> nil
      end

    %{
      position: :end,
      anchor: anchor,
      text: dgettext("content_proposals", "At the end of %{block}", block: block_label(entry, field, parent, proposal))
    }
  end

  defp placement(:append, nil, entry, field, _proposal) do
    anchor =
      case entry && Map.get(entry, :"entry_#{field}", []) do
        [_ | _] = joins -> block_anchor(List.last(joins).block)
        _ -> nil
      end

    %{position: :end, anchor: anchor, text: dgettext("content_proposals", "At the end")}
  end

  defp placement({side, uid}, _parent, entry, field, proposal) do
    label = block_label(entry, field, uid, proposal)

    text =
      if side == :before,
        do: dgettext("content_proposals", "Before %{block}", block: label),
        else: dgettext("content_proposals", "After %{block}", block: label)

    anchor =
      case saved_block(entry, field, uid) do
        nil -> %{module: label, excerpt: nil}
        block -> block_anchor(block)
      end

    %{position: side, anchor: anchor, text: text}
  end

  defp block_anchor(block) do
    %{
      module:
        (block.module_id && module_label({block.module_origin || :local, block.module_id})) ||
          dgettext("content_proposals", "Block"),
      excerpt: describe(block)
    }
  end

  # A saved block is named by its module and the start of its text; a block
  # the proposal inserts, by its module.
  defp block_label(entry, field, uid, proposal) do
    case find_saved(entry, field, uid) do
      nil ->
        case Enum.find(proposal.operations, &match?(%InsertBlock{uid: ^uid}, &1)) do
          %InsertBlock{module: module} ->
            dgettext("content_proposals", "the new %{module} block", module: module_label(module))

          nil ->
            dgettext("content_proposals", "a block")
        end

      {block, parent, index} ->
        name = "“#{block_name(block)}”"
        text = describe(block)

        position =
          parent &&
            dgettext("content_proposals", "%{position} of %{count} in “%{parent}”",
              position: index + 1,
              count: length(parent.children),
              parent: block_name(parent)
            )

        text = if text == block_name(block), do: nil, else: text
        Enum.join(Enum.reject([name, position, text], &(&1 in [nil, ""])), " · ")
    end
  end

  # What a block is about: the entry a link variable points to — a project
  # block names its project — or else the start of its text, or of its first
  # text variable (a team member block holds only a name and a role).
  defp describe(block) do
    Enum.find_value(block.vars || [], fn
      %{type: :link, identifier: %{title: title}} when is_binary(title) and title != "" -> title
      _ -> nil
    end) ||
      block.refs |> Enum.find_value(&text_of/1) |> excerpt() ||
      Enum.find_value(block.vars || [], fn
        %{type: type, value: value} when type in [:string, :text] and is_binary(value) and value != "" -> excerpt(value)
        _ -> nil
      end)
  end

  defp block_name(block) do
    (block.module_id && module_label({block.module_origin || :local, block.module_id})) ||
      dgettext("content_proposals", "Block")
  end

  defp find_saved(nil, _field, _uid), do: nil
  defp find_saved(entry, field, uid), do: entry |> Map.get(:"entry_#{field}", []) |> BlockTree.find_saved(uid)

  defp saved_block(entry, field, uid) do
    case find_saved(entry, field, uid) do
      {block, _parent, _index} -> block
      nil -> nil
    end
  end

  # A setting as the editor knows it: the variable's label, and the option
  # label of a select next to its value, with the saved value before it.
  defp value_view({key, value}, saved, uid, proposal) do
    var = saved && Enum.find(saved.vars, &(&1.key == key))
    var = var || module_var(uid, key, proposal)

    %{
      name: key,
      label: var && var.label,
      before: saved && var && saved_value(var),
      value: option(var, value),
      media: media_value(value)
    }
  end

  defp saved_value(%{type: :boolean} = var), do: var.value_boolean
  defp saved_value(%{type: :link, identifier: %{title: title}}) when is_binary(title), do: title
  defp saved_value(%{type: type}) when type in [:image, :video], do: nil
  defp saved_value(var), do: option(var, var.value)

  defp media_value({kind, id}) when kind in [:image, :video], do: %{kind: kind, id: id}
  defp media_value({:gallery, [{kind, id} | _]}), do: %{kind: kind, id: id}
  defp media_value(_), do: nil

  defp module_var(uid, key, proposal) do
    with %InsertBlock{module: module} <- Enum.find(proposal.operations, &match?(%InsertBlock{uid: ^uid}, &1)),
         %{vars: vars} <- fetch_module(module) do
      Enum.find(vars || [], &(&1.key == key))
    else
      _ -> nil
    end
  end

  defp option(%{type: :select, options: options}, value) when is_binary(value) do
    case Enum.find(options || [], &(&1.value == value)) do
      %{label: label} when label in [nil, ""] -> value
      # "40%" says what "40" means; "Half (50)" needs the value beside it.
      %{label: label} -> if String.contains?(label, value), do: label, else: "#{label} (#{value})"
      _ -> value
    end
  end

  defp option(_var, {:entry, schema, id}) do
    case Content.get_identifier(schema, %{id: id}) do
      {:ok, %{title: title}} when is_binary(title) -> title
      _ -> "##{id}"
    end
  end

  defp option(_var, {kind, _id}) when kind in [:image, :video], do: nil
  defp option(_var, {:file, id}), do: dgettext("content_proposals", "File #%{id}", id: id)

  defp option(_var, {:gallery, items}),
    do: dngettext("content_proposals", "%{count} item", "%{count} items", length(items))

  defp option(_var, value), do: shorten(value)

  defp descendants(nil), do: 0
  defp descendants(block), do: Enum.reduce(block.children || [], 0, &(&2 + 1 + descendants(&1)))

  # The first image or video of a block, shown so the reviewer recognises it.
  defp block_media(nil), do: []

  defp block_media(block) do
    block.refs
    |> Enum.find_value(fn ref ->
      Enum.find_value([:image, :video], fn kind ->
        id = Map.get(ref, :"#{kind}_id")
        id && %{ref: ref.name, kind: kind, id: id}
      end)
    end)
    |> List.wrap()
  end

  defp saved_text(entry, field, uid, ref) do
    with %{refs: refs} <- saved_block(entry, field, uid),
         %{} = ref <- Enum.find(refs, &(&1.name == to_string(ref))) do
      text_of(ref)
    end
  end

  defp text_of(%{data: %{type: type, data: %{text: text}}}) when type in ["text", "header"] and is_binary(text),
    do: text

  defp text_of(_), do: nil

  # Named preview targets, for content types with more than one view.
  defp preview_targets(schema) do
    for target <- Brando.LivePreview.get_targets(schema) do
      {to_string(target.name), target.label || Brando.Utils.humanize(to_string(target.name))}
    end
  end

  # The blocks a page preview outlines: inserted blocks and changed ones.
  defp uids_of(changes),
    do: changes |> Enum.flat_map(&[Map.get(&1, :uid) | Map.get(&1, :uids, [])]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  defp media_of(changes) do
    fields = for %{fields: fields} <- changes, %{media: %{kind: kind, id: id}} <- fields, do: {kind, id}
    blocks = for %{media: media} <- changes, is_list(media), %{kind: kind, id: id} <- media, do: {kind, id}
    Enum.uniq(fields ++ blocks)
  end

  defp problems(proposal, target) do
    key = Proposal.key(target)

    Enum.filter(proposal.problems, fn problem ->
      problem_target = problem[:target]

      (problem_target && (problem_target == target or problem_target == key)) ||
        (is_integer(problem[:operation]) && Map.get(Enum.at(proposal.operations, problem.operation), :target) == target)
    end)
  end

  # Fields in the order an editor reads them: title first, then the rest.
  defp order_fields(fields) do
    Enum.sort_by(fields, fn {name, _} ->
      {Enum.find_index(~w(title name slug uri language), &(&1 == name)) || 99, name}
    end)
  end

  # A field as the editor knows it: its label, and its value as text or as
  # media. Asset ids show the asset; related ids the record's title.
  defp field_view(schema, name, value) do
    case asset_kind(schema, name) do
      nil -> %{name: label_for(name), value: display(schema, name, value), media: nil}
      kind -> %{name: label_for(String.replace_suffix(name, "_id", "")), value: nil, media: media_ref(kind, value)}
    end
  end

  defp label_for(name), do: Brando.Content.Transfer.Labels.field(name)

  defp asset_kind(schema, name) do
    Enum.find_value(Brando.Blueprint.Assets.__assets__(schema), fn
      %{name: asset, type: type} when type in [:image, :video] -> if "#{asset}_id" == name, do: type
      _ -> nil
    end)
  rescue
    _ -> nil
  end

  defp media_ref(kind, {kind, id}), do: media_ref(kind, id)
  defp media_ref(kind, id) when is_integer(id), do: %{kind: kind, id: id}
  defp media_ref(_, _), do: nil

  defp display(_schema, "language", value) when is_binary(value) or (is_atom(value) and not is_nil(value)) do
    code = to_string(value)

    case Enum.find(Brando.config(:languages) || [], &(to_string(&1[:value]) == code)) do
      nil -> code
      language -> Brando.Content.Transfer.Labels.language(code, language[:text])
    end
  end

  defp display(schema, name, id) when is_integer(id) do
    with true <- String.ends_with?(name, "_id"),
         relation = String.to_existing_atom(String.replace_suffix(name, "_id", "")),
         %{related: related} <- schema.__schema__(:association, relation),
         %{} = record <- Brando.Repo.get(related, id) do
      Map.get(record, :title) || Map.get(record, :name) || "##{id}"
    else
      _ -> id
    end
  rescue
    _ -> id
  end

  defp display(schema, name, value) when is_list(value), do: EntryFields.display(schema, name, value) || shorten(value)
  defp display(_schema, _name, value) when is_binary(value), do: excerpt(value)
  defp display(_schema, _name, value), do: shorten(value)

  defp first_mention(proposal, target) do
    Enum.find_index(proposal.operations, fn
      %CreateEntry{ref: ref} -> {:new, ref} == target
      %CopyBlock{to_target: to} = op when not is_nil(to) -> target in [op.target, to]
      op -> Map.get(op, :target) == target
    end) || 0
  end

  # A saved field as the reviewer reads it; a list by its titles.
  defp saved_value(entry, name) do
    if Map.has_key?(EntryFields.lists(entry.__struct__), name),
      do: entry |> EntryFields.preload([name]) |> EntryFields.current(name),
      else: display(entry.__struct__, name, current(entry, name))
  end

  defp current(entry, name) do
    Map.get(entry, String.to_existing_atom(name))
  rescue
    ArgumentError -> nil
  end

  defp admin_url(schema, id) do
    schema.__admin_route__(:update, [id])
  rescue
    _ -> nil
  end

  defp module_label(reference) do
    case fetch_module(reference) do
      nil -> nil
      module -> label(module.name)
    end
  end

  defp fetch_module(reference) do
    {origin, id} = Content.SharedLibrary.reference(reference)
    Content.fetch_module(id, origin)
  rescue
    _ -> nil
  end

  # Module names in the admin's language, falling back to English.
  defp label(%{} = map),
    do: map[Gettext.get_locale(Brando.Gettext)] || map["en"] || map |> Map.values() |> List.first()

  defp label(value), do: value

  defp excerpt(nil), do: nil

  defp excerpt(text) do
    text |> HtmlSanitizeEx.strip_tags() |> String.replace(~r/\s+/, " ") |> String.trim() |> shorten()
  end

  defp shorten(value) when is_binary(value) and byte_size(value) > @excerpt, do: String.slice(value, 0, @excerpt) <> "…"
  defp shorten(value) when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value), do: value
  defp shorten({:new, ref}), do: dgettext("content_proposals", "the new entry %{ref}", ref: ref)
  defp shorten(value), do: inspect(value)

  defp blank(""), do: nil
  defp blank(value), do: value
end
