defmodule Brando.MarkdownSources.Renderer do
  @moduledoc "Safe external Markdown; intentionally independent of trusted CMS Markdown options."
  @tags ~w(p br hr em strong del pre code blockquote ul ol li h1 h2 h3 h4 h5 h6 table thead tbody tr th td a img)

  def render(%{markdown: markdown} = document) do
    with {:ok, html} <-
           MDEx.to_html(markdown, extension: [autolink: true, strikethrough: true, table: true], render: [unsafe: false]),
         {:ok, tree} <- Floki.parse_fragment(html) do
      {safe, _} = sanitize(tree, document, %{})
      {:ok, Floki.raw_html(safe)}
    else
      _ -> {:error, :invalid_markdown}
    end
  end

  defp sanitize(nodes, document, counts) do
    Enum.map_reduce(nodes, counts, fn
      text, acc when is_binary(text) ->
        {text, acc}

      {tag, attrs, children}, acc when tag in @tags ->
        {children, acc} = sanitize(children, document, acc)
        attrs = Enum.flat_map(attrs, &attribute(tag, &1, document))
        {attrs, acc} = heading(tag, attrs, children, acc)
        {{tag, attrs, children}, acc}

      _, acc ->
        {"", acc}
    end)
  end

  defp attribute(tag, {key, value}, doc) when (tag == "a" and key == "href") or (tag == "img" and key == "src") do
    case safe_url(value, doc, tag) do
      nil -> []
      url -> [{key, url}]
    end
  end

  defp attribute(tag, {key, value}, _) when key == "title" or (tag == "img" and key == "alt"), do: [{key, value}]

  defp attribute("code", {"class", "language-" <> language}, _) do
    if Regex.match?(~r/\A[a-zA-Z0-9_-]{1,40}\z/, language), do: [{"class", "language-" <> language}], else: []
  end

  defp attribute(_, _, _), do: []

  def safe_url(value, document, tag) do
    uri = URI.parse(value)

    cond do
      Regex.match?(~r/[\x00-\x20\x7f\\]/, value) ->
        nil

      uri.scheme in ["https", "http"] and is_binary(uri.host) and is_nil(uri.userinfo) ->
        value

      tag == "a" and uri.scheme == "mailto" ->
        value

      is_nil(uri.scheme) and is_nil(uri.host) and String.starts_with?(value, "#") ->
        value

      is_nil(uri.scheme) and is_nil(uri.host) and not Regex.match?(~r/%(?:2e|2f|5c)/i, value) ->
        base = if tag == "img", do: "https://raw.githubusercontent.com/", else: "https://github.com/"
        middle = if tag == "img", do: "/", else: "/blob/"
        path = document.path |> String.split("/") |> Enum.map_join("/", &URI.encode/1)
        url = base <> document.repository <> middle <> document.commit <> "/" <> path
        result = URI.merge(url, value)
        # A relative path cannot escape the selected repository/commit root.
        root = "/" <> document.repository <> middle <> document.commit <> "/"
        if String.starts_with?(result.path || "", root), do: URI.to_string(result)

      true ->
        nil
    end
  rescue
    _ -> nil
  end

  defp heading(tag, attrs, children, counts) when tag in ~w(h1 h2 h3 h4 h5 h6) do
    slug = children |> Floki.text() |> Slug.slugify() |> then(&if(&1 == "", do: "section", else: &1))
    number = Map.get(counts, slug, 0)
    {id, number} = unique_heading_id(slug, number, counts)
    {[{"id", id} | attrs], counts |> Map.put(slug, number + 1) |> Map.put({:used, id}, true)}
  end

  defp heading(_, attrs, _, counts), do: {attrs, counts}

  defp unique_heading_id(slug, number, counts) do
    id = if number == 0, do: slug, else: "#{slug}-#{number}"
    if Map.has_key?(counts, {:used, id}), do: unique_heading_id(slug, number + 1, counts), else: {id, number}
  end
end
