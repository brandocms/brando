defmodule Brando.Upgrade.Snapshot.Diff do
  @moduledoc """
  Compares two responses for the same URL in layers, so one kind of change
  does not hide another:

    * `:status` — the status code, and the `location` of a redirect
    * `:text` — the visible text in document order: text nodes with their
      whitespace collapsed, and `[img alt="…"]` for each image, with
      `<head>`, scripts, styles, `<noscript>`, `<template>` and inline SVG
      left out. A body that is not HTML (`robots.txt`, `sitemap.xml`) is
      compared line by line here.
    * `:head` — the `<head>`'s `meta`, `link`, `title`, `base` and JSON-LD
      tags as a set, each with its attributes sorted (`content` and `href`
      last), so reordering is not a change. A `nonce` and the CSRF token's value are left out, since they
      change on every request.
    * `:structure` — the sequence of elements in the body, each as its tag,
      its classes and the names of its `data-*` attributes
      (`div.video-wrapper[data-smart-video data-src]`), so markup that moved
      shows even when the text is the same.

  Text and structure are compared as sequences (removed lines `- `, added
  `+ `, in document order); the head as a set.
  """

  @layers [:status, :text, :head, :structure]
  @skipped_text ~w(head script style noscript template svg)
  @opaque_elements ~w(script style template svg)
  @head_tags ~w(meta link title base)
  # Sorted last, so a tag's lines sort by what it is (`meta property="og:locale"`)
  # rather than by its value.
  @value_attributes ~w(content href)

  @type layer :: %{layer: atom(), summary: String.t(), lines: [String.t()]}

  @doc "The layers, in report order."
  def layers, do: @layers

  @doc """
  The layers in which `after_page` differs from `before_page`, each with a
  one-line summary and its changed lines; `[]` when they are the same.
  `:layers` limits the comparison to some of them.
  """
  @spec compare(map(), map(), keyword()) :: [layer()]
  def compare(before_page, after_page, opts \\ []) do
    wanted = Keyword.get(opts, :layers, @layers)
    before_doc = parse(before_page)
    after_doc = parse(after_page)

    @layers
    |> Enum.filter(&(&1 in wanted))
    |> Enum.flat_map(fn layer ->
      case compare_layer(layer, {before_page, before_doc}, {after_page, after_doc}) do
        nil -> []
        result -> [Map.put(result, :layer, layer)]
      end
    end)
  end

  defp compare_layer(:status, {before_page, _}, {after_page, _}) do
    before_status = status_line(before_page)
    after_status = status_line(after_page)

    if before_status != after_status,
      do: %{summary: "#{before_status} → #{after_status}", lines: []}
  end

  defp compare_layer(:text, {before_page, before_doc}, {after_page, after_doc}) do
    sequence_diff(text_of(before_page, before_doc), text_of(after_page, after_doc))
  end

  defp compare_layer(:head, {_, before_doc}, {_, after_doc}) do
    set_diff(head(before_doc), head(after_doc))
  end

  defp compare_layer(:structure, {_, before_doc}, {_, after_doc}) do
    sequence_diff(structure(before_doc), structure(after_doc))
  end

  defp status_line(%{status: nil, body: body}), do: "no response (#{body})"
  defp status_line(%{status: status, location: location}) when is_binary(location), do: "#{status} #{location}"
  defp status_line(%{status: status}), do: to_string(status)

  # The parsed document, or nil for a body that is not HTML.
  defp parse(%{body: body} = page) do
    if html?(page) do
      case Floki.parse_document(body) do
        {:ok, document} -> document
        {:error, _} -> nil
      end
    end
  end

  defp html?(%{content_type: content_type}) when is_binary(content_type), do: content_type =~ "html"
  defp html?(%{body: body}), do: body =~ ~r/<(!doctype html|html|body)[\s>]/i

  defp text_of(_page, document) when is_list(document), do: text(document)

  defp text_of(%{body: body}, nil) do
    body
    |> String.split(~r/\R/)
    |> Enum.map(&collapse/1)
    |> Enum.reject(&(&1 == ""))
  end

  @doc "The visible text of a parsed document, one entry per text node or image."
  @spec text(Floki.html_tree()) :: [String.t()]
  def text(document) do
    document |> text_nodes([]) |> Enum.reverse()
  end

  defp text_nodes(nodes, acc) when is_list(nodes), do: Enum.reduce(nodes, acc, &text_nodes/2)

  defp text_nodes(text, acc) when is_binary(text) do
    case collapse(text) do
      "" -> acc
      text -> [text | acc]
    end
  end

  defp text_nodes({"img", attrs, _children}, acc) do
    alt = attrs |> List.keyfind("alt", 0, {"alt", ""}) |> elem(1)
    [~s([img alt="#{collapse(alt)}"]) | acc]
  end

  defp text_nodes({tag, _attrs, _children}, acc) when tag in @skipped_text, do: acc
  defp text_nodes({_tag, _attrs, children}, acc), do: text_nodes(children, acc)
  defp text_nodes(_other, acc), do: acc

  @doc """
  The `<head>` tags of a parsed document, each as `tag attr="value" …` with
  the attributes sorted; a `title` is followed by its text and JSON-LD by its
  content.
  """
  @spec head(Floki.html_tree()) :: [String.t()]
  def head(nil), do: []

  def head(document) do
    document
    |> Floki.find("head")
    |> Enum.flat_map(&head_tags(&1, []))
    |> Enum.reverse()
  end

  defp head_tags({"script", attrs, children} = node, acc) do
    if List.keyfind(attrs, "type", 0) == {"type", "application/ld+json"},
      do: [head_tag(node) <> " " <> collapse(Floki.text(children, js: true)) | acc],
      else: acc
  end

  defp head_tags({"title", _attrs, children} = node, acc),
    do: [head_tag(node) <> " " <> collapse(Floki.text(children)) | acc]

  defp head_tags({tag, _attrs, _children} = node, acc) when tag in @head_tags, do: [head_tag(node) | acc]
  defp head_tags({_tag, _attrs, children}, acc), do: Enum.reduce(children, acc, &head_tags/2)
  defp head_tags(_other, acc), do: acc

  defp head_tag({tag, attrs, _children}) do
    csrf? = List.keyfind(attrs, "name", 0) == {"name", "csrf-token"}

    attrs
    |> Enum.reject(fn {name, _} -> name == "nonce" or (csrf? and name == "content") end)
    |> Enum.sort_by(fn {name, value} -> {name in @value_attributes, name, value} end)
    |> Enum.map(fn {name, value} -> ~s( #{name}="#{value}") end)
    |> then(&IO.iodata_to_binary([tag | &1]))
  end

  @doc """
  The elements of a parsed document's body in order, each as its tag, sorted
  classes and sorted `data-*` attribute names: `video.hero[data-src data-video]`.
  """
  @spec structure(Floki.html_tree()) :: [String.t()]
  def structure(nil), do: []

  def structure(document) do
    root =
      case Floki.find(document, "body") do
        [] -> document
        body -> body
      end

    root |> elements([]) |> Enum.reverse()
  end

  defp elements(nodes, acc) when is_list(nodes), do: Enum.reduce(nodes, acc, &elements/2)

  defp elements({tag, attrs, children}, acc) when is_binary(tag) do
    acc = [signature(tag, attrs) | acc]
    if tag in @opaque_elements, do: acc, else: elements(children, acc)
  end

  defp elements(_other, acc), do: acc

  defp signature(tag, attrs) do
    classes =
      attrs
      |> Enum.filter(&(elem(&1, 0) == "class"))
      |> Enum.flat_map(&String.split(elem(&1, 1)))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map_join(&("." <> &1))

    data =
      attrs
      |> Enum.map(&elem(&1, 0))
      |> Enum.filter(&String.starts_with?(&1, "data-"))
      |> Enum.uniq()
      |> Enum.sort()

    data = if data == [], do: "", else: "[#{Enum.join(data, " ")}]"
    tag <> classes <> data
  end

  defp collapse(text), do: text |> String.split() |> Enum.join(" ")

  defp sequence_diff(same, same), do: nil

  defp sequence_diff(before_items, after_items) do
    edits = List.myers_difference(before_items, after_items)
    removed = edits |> Keyword.get_values(:del) |> Enum.map(&length/1) |> Enum.sum()
    added = edits |> Keyword.get_values(:ins) |> Enum.map(&length/1) |> Enum.sum()

    %{summary: "-#{removed} +#{added}", lines: Enum.flat_map(edits, &edit_lines/1)}
  end

  defp edit_lines({:del, items}), do: Enum.map(items, &("- " <> &1))
  defp edit_lines({:ins, items}), do: Enum.map(items, &("+ " <> &1))
  defp edit_lines({:eq, _items}), do: []

  defp set_diff(before_items, after_items) do
    removed = Enum.sort(before_items -- after_items)
    added = Enum.sort(after_items -- before_items)

    if removed != [] or added != [] do
      %{
        summary: "-#{length(removed)} +#{length(added)}",
        lines: Enum.map(removed, &("- " <> &1)) ++ Enum.map(added, &("+ " <> &1))
      }
    end
  end
end
