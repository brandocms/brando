defmodule Brando.Villain.Footnotes do
  @moduledoc """
  Resolves rich-text references in final rendered order, across block boundaries.

  `render/2` returns the body and ordered, rendered notes separately. `to_html/2`
  adds a semantic endnote outlet. Slot bodies remain ordinary Villain modules.
  Numbers belong to a render scope, never to persisted Tiptap content.
  """
  alias Brando.Content.BlockSlots
  alias Brando.Villain.Parser

  @marker "data-footnote-uid"
  @definition "data-brando-footnote"

  @doc """
  Renders a Blueprint rich-text field and its owned notes as `%{html:, notes:}`.
  Preload the configured `entry_<blocks>` relation and its block trees, just as
  for ordinary Villain rendering. `enabled: false` prevents authoring new notes
  while preserving the rendering of existing content.
  """
  def render_field(%schema{} = entry, field, opts \\ []) do
    html = Map.get(entry, field) || ""

    case Brando.Blueprint.Forms.Footnotes.field(schema, field) do
      nil ->
        %{html: html, notes: []}

      config ->
        association = String.to_existing_atom("entry_#{config.blocks}")

        slots =
          case Map.get(entry, association) do
            entries when is_list(entries) ->
              entries
              |> Enum.map(& &1.block)
              |> Enum.filter(&(&1.slot_kind == :footnote && &1.slot_name == to_string(field) && &1.active))

            _ ->
              raise ArgumentError, "Preload #{association} and its block tree before rendering #{field} footnotes"
          end

        definitions =
          Enum.map(slots, fn slot ->
            body = Brando.Villain.render_block(slot, entry, opts)
            ["<template ", @definition, "=\"", escape(slot.uid), "\">", body, "</template>"]
          end)

        opts = Keyword.put_new(opts, :scope, "#{schema.__naming__().singular}-#{entry.id}-#{field}")
        render([html, definitions], opts)
    end
  end

  @doc false
  def attach(html, owner, opts) do
    html = IO.iodata_to_binary(html)
    notes = BlockSlots.footnotes(owner)

    if notes == [] || !String.contains?(html, @marker) do
      html
    else
      definitions =
        notes
        |> Enum.filter(& &1.active)
        |> Enum.map(fn slot ->
          body = Parser.render_block_slot(slot, Map.put(opts, :skip_children, false))
          ["<template ", @definition, "=\"", escape(slot.uid), "\">", body, "</template>"]
        end)

      IO.iodata_to_binary([html, definitions])
    end
  end

  @doc """
  Returns `%{html: body, notes: notes}` with one running number per note.

  Give `:scope` a distinct value when separately rendering multiple fields on
  one page. To share a counter, combine their unfinalized HTML before calling
  this function. An existing endnote result can also be composed and renumbered.
  """
  def render(html, opts \\ []) do
    html = IO.iodata_to_binary(html || "")

    if String.contains?(html, @marker) || String.contains?(html, @definition) do
      tree = Floki.parse_fragment!(html)
      {tree, definitions} = extract(tree, %{})
      scope = opts |> Keyword.get(:scope, "article") |> to_string() |> safe_id()
      state = %{definitions: definitions, order: [], notes: %{}, scope: scope, occurrence: 0}
      {tree, state} = walk(tree, state)
      notes = Enum.map(state.order, &Map.fetch!(state.notes, &1))
      %{html: Floki.raw_html(tree), notes: notes}
    else
      %{html: html, notes: []}
    end
  end

  @doc "Renders the body followed by an accessible endnote list."
  def to_html(%{html: html, notes: []}, _opts), do: html

  def to_html(%{html: html, notes: notes}, opts) do
    title = Keyword.get(opts, :title, "Notes & sources")
    IO.iodata_to_binary([html, outlet(notes, title)])
  end

  def to_html(result), do: to_html(result, [])

  @doc "Renders an endnote outlet from the structured notes returned by render/2."
  def outlet(notes, title \\ "Notes & sources")
  def outlet([], _title), do: ""

  def outlet(notes, title) do
    items =
      Enum.map(notes, fn note ->
        backlinks =
          Enum.with_index(note.reference_ids, 1)
          |> Enum.map(fn {id, index} ->
            label = "Return to reference #{note.number}" <> if(length(note.reference_ids) > 1, do: ".#{index}", else: "")
            ["<a class=\"footnote-backlink\" role=\"doc-backlink\" href=\"#", id, "\" aria-label=\"", label, "\">↩</a>"]
          end)

        [
          "<li id=\"",
          note.id,
          "\" data-brando-note=\"",
          escape(note.uid),
          "\" value=\"",
          to_string(note.number),
          "\"><div data-footnote-body>",
          note.html,
          "</div><nav aria-label=\"Back to text\">",
          backlinks,
          "</nav></li>"
        ]
      end)

    [
      "<section class=\"footnotes\" role=\"doc-endnotes\" data-brando-footnotes><h2>",
      escape(title),
      "</h2><ol>",
      items,
      "</ol></section>"
    ]
  end

  defp extract(nodes, definitions) do
    Enum.reduce(nodes, {[], definitions}, fn
      {"template", attrs, children} = node, {acc, defs} ->
        if uid = attr(attrs, @definition) do
          {acc, Map.put_new(defs, uid, Floki.raw_html(children))}
        else
          {[node | acc], defs}
        end

      {tag, attrs, children}, {acc, defs} ->
        if attr(attrs, "data-brando-footnotes") != nil do
          defs =
            Enum.reduce(Floki.find(children, "[data-brando-note]"), defs, fn {_, note_attrs, body}, defs ->
              content = Floki.find(body, "[data-footnote-body]") |> Enum.flat_map(fn {_, _, content} -> content end)
              Map.put_new(defs, attr(note_attrs, "data-brando-note"), Floki.raw_html(content))
            end)

          {acc, defs}
        else
          {children, defs} = extract(children, defs)
          {[{tag, attrs, children} | acc], defs}
        end

      node, {acc, defs} ->
        {[node | acc], defs}
    end)
    |> then(fn {nodes, defs} -> {Enum.reverse(nodes), defs} end)
  end

  defp walk(nodes, state) do
    Enum.map_reduce(nodes, state, fn
      {tag, attrs, children} = node, state ->
        uid = attr(attrs, @marker)

        cond do
          uid && Map.has_key?(state.definitions, uid) ->
            marker(uid, state)

          uid ->
            {{"span", [{"class", "footnote-unresolved"}, {"aria-label", "Missing footnote"}], ["?"]}, state}

          tag in ["script", "style", "template"] ->
            {node, state}

          true ->
            {children, state} = walk(children, state)
            {{tag, attrs, children}, state}
        end

      node, state ->
        {node, state}
    end)
  end

  defp marker(uid, state) do
    note =
      Map.get(state.notes, uid, %{
        uid: uid,
        number: length(state.order) + 1,
        id: "fn-#{state.scope}-#{safe_id(uid)}",
        html: Map.fetch!(state.definitions, uid),
        reference_ids: []
      })

    occurrence = state.occurrence + 1
    reference_id = "fnref-#{state.scope}-#{occurrence}"
    note = %{note | reference_ids: note.reference_ids ++ [reference_id]}
    order = if Map.has_key?(state.notes, uid), do: state.order, else: state.order ++ [uid]
    state = %{state | notes: Map.put(state.notes, uid, note), order: order, occurrence: occurrence}

    link =
      {"a",
       [
         {"href", "##{note.id}"},
         {"id", reference_id},
         {"role", "doc-noteref"},
         {"aria-label", "Footnote #{note.number}"}
       ], [to_string(note.number)]}

    {{"sup", [{@marker, uid}, {"class", "footnote-reference"}], [link]}, state}
  end

  defp attr(attrs, name), do: List.keyfind(attrs, name, 0, {name, nil}) |> elem(1)
  defp safe_id(value), do: Base.url_encode64(value, padding: false)
  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
