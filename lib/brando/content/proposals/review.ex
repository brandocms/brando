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
    CreateEntry,
    InsertBlock,
    Proposal,
    SetBlockMedia,
    SetBlockText,
    SetBlockValues,
    SetFields
  }

  alias Brando.Content.Transfer.Catalog

  @excerpt 90

  @doc "Review cards for `proposal`."
  @spec entries(Proposal.t()) :: [map()]
  def entries(%Proposal{} = proposal) do
    proposal.targets
    |> Enum.sort_by(fn {target, _} -> first_mention(proposal, target) end)
    |> Enum.map(fn {target, value} -> entry(target, value, proposal) end)
  end

  @doc "Every `{kind, id}` media reference in the review cards, for batch loading."
  @spec media([map()]) :: [{:image | :video, integer()}]
  def media(entries), do: entries |> Enum.flat_map(& &1.media) |> Enum.uniq()

  defp entry({:new, ref} = target, schema, proposal) do
    %CreateEntry{fields: fields} = Enum.find(proposal.operations, &match?(%CreateEntry{ref: ^ref}, &1))

    changes = [%{type: :create, fields: Enum.map(fields, fn {k, v} -> %{name: k, value: shorten(v)} end)}]
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
          do: %{name: name, before: shorten(current(entry, name)), value: shorten(value)}

    if fields == [], do: [], else: [%{type: :fields, fields: fields}]
  end

  defp block_changes(target, entry, proposal) do
    Enum.flat_map(proposal.operations, fn
      %InsertBlock{target: ^target} = op ->
        module = fetch_module(op.module)

        [
          %{
            type: :insert_block,
            uid: op.uid,
            field: op.field,
            module: module && label(module.name),
            placement: placement(op.placement, entry, op.field, proposal),
            values: Enum.map(op.values, fn {k, v} -> %{name: k, value: shorten(v)} end),
            texts: Enum.map(op.texts, fn {ref, text} -> %{ref: ref, text: excerpt(text)} end),
            media: Enum.map(op.media, fn {ref, {kind, id}} -> %{ref: ref, kind: kind, id: id} end)
          }
        ]

      %SetBlockMedia{target: ^target} = op ->
        {kind, id} = op.asset

        [
          %{
            type: :block_media,
            uid: op.block_uid,
            block: block_label(entry, op.field, op.block_uid, proposal),
            ref: to_string(op.ref),
            media: [%{ref: to_string(op.ref), kind: kind, id: id}]
          }
        ]

      %SetBlockText{target: ^target} = op ->
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

      %SetBlockValues{target: ^target} = op ->
        [
          %{
            type: :block_values,
            uid: op.block_uid,
            block: block_label(entry, op.field, op.block_uid, proposal),
            values: Enum.map(op.values, fn {k, v} -> %{name: k, value: shorten(v)} end)
          }
        ]

      _ ->
        []
    end)
  end

  defp placement(:append, _entry, _field, _proposal), do: dgettext("content_proposals", "At the end")

  defp placement({:before, uid}, entry, field, proposal),
    do: dgettext("content_proposals", "Before %{block}", block: block_label(entry, field, uid, proposal))

  defp placement({:after, uid}, entry, field, proposal),
    do: dgettext("content_proposals", "After %{block}", block: block_label(entry, field, uid, proposal))

  # A saved block is named by its module and the start of its text; a block
  # the proposal inserts, by its module.
  defp block_label(entry, field, uid, proposal) do
    case saved_block(entry, field, uid) do
      nil ->
        case Enum.find(proposal.operations, &match?(%InsertBlock{uid: ^uid}, &1)) do
          %InsertBlock{module: module} ->
            dgettext("content_proposals", "the new %{module} block", module: module_label(module))

          nil ->
            dgettext("content_proposals", "a block")
        end

      block ->
        name = block.module_id && module_label({block.module_origin || :local, block.module_id})
        text = block.refs |> Enum.find_value(&text_of/1) |> excerpt()
        Enum.join(Enum.reject(["“#{name || dgettext("content_proposals", "Block")}”", text], &(&1 in [nil, ""])), " · ")
    end
  end

  defp saved_block(nil, _field, _uid), do: nil

  defp saved_block(entry, field, uid) do
    entry |> Map.get(:"entry_#{field}", []) |> Enum.find_value(&(&1.block.uid == uid && &1.block))
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
  defp uids_of(changes), do: changes |> Enum.map(&Map.get(&1, :uid)) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  defp media_of(changes), do: for(%{media: media} <- changes, %{kind: kind, id: id} <- media, do: {kind, id})

  defp problems(proposal, target) do
    key = Proposal.key(target)

    Enum.filter(proposal.problems, fn problem ->
      problem_target = problem[:target]

      (problem_target && (problem_target == target or problem_target == key)) ||
        (is_integer(problem[:operation]) && Map.get(Enum.at(proposal.operations, problem.operation), :target) == target)
    end)
  end

  defp first_mention(proposal, target) do
    Enum.find_index(proposal.operations, fn
      %CreateEntry{ref: ref} -> {:new, ref} == target
      op -> Map.get(op, :target) == target
    end) || 0
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

  defp label(%{} = map), do: map["en"] || map |> Map.values() |> List.first()
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
