defmodule Brando.SEO.Markdown do
  @moduledoc """
  The Markdown version of an entry's page, for AI tools and answer engines.

  An entry's page is also served as Markdown at its URL with `.md` appended
  (`/projects/sommerro.md`), and at its normal URL to a request that asks for
  `text/markdown` in its `Accept` header. The HTML page names it with
  `<link rel="alternate" type="text/markdown">`. `Brando.Plug.Markdown`
  serves it; see [Markdown alternates](markdown_alternates.html).

  A blueprint has a Markdown version when it has a URL of its own, block
  fields (`Brando.Trait.Blocks`) and `Brando.Trait.Meta`. Turn it off with
  `trait :meta, markdown: false`.

  The Markdown is only ever served for the entry the page's controller
  loaded and passed to `put_meta/3`, `put_hreflang/2` or `put_json_ld/3`, so
  it follows the same rules as the HTML: a draft, a scheduled entry, another
  site's entry or a page behind a login is not found as Markdown either. As
  a second check, the entry must be published, past any publish time and not
  deleted.

  The document is the entry's title as a heading, then its block fields
  rendered by `Brando.Villain.Markdown`.
  """
  alias Brando.Blueprint.URL
  alias Brando.Content.BlockPreloads
  alias Brando.Villain.Markdown, as: Renderer

  @doc """
  Whether entries of `schema` have a Markdown version: a URL, block fields and
  the meta trait, without `trait :meta, markdown: false`.
  """
  @spec enabled?(module()) :: boolean()
  def enabled?(schema) when is_atom(schema) do
    Code.ensure_loaded?(schema) and function_exported?(schema, :__trait__, 1) and
      function_exported?(schema, :__absolute_url__, 1) and blocks?(schema) and option(schema) != false
  end

  def enabled?(_schema), do: false

  defp blocks?(schema), do: schema.has_trait(Brando.Trait.Blocks) and schema.__blocks_fields__() != []

  defp option(schema) do
    case schema.__trait__(Brando.Trait.Meta) do
      false -> false
      opts when is_list(opts) -> Keyword.get(opts, :markdown, true)
      opts when is_map(opts) -> Map.get(opts, :markdown, true)
      _ -> true
    end
  end

  @doc """
  Whether `entry` is served as Markdown: its blueprint has a Markdown version,
  it has a URL, and it is published, past its publish time and not deleted.
  """
  @spec available?(term()) :: boolean()
  def available?(%{__struct__: schema} = entry) do
    enabled?(schema) and URL.has_url?(entry) and published?(entry)
  end

  def available?(_entry), do: false

  @doc false
  def published?(entry) do
    Map.get(entry, :status, :published) == :published and
      is_nil(Map.get(entry, :deleted_at)) and
      not future?(Map.get(entry, :publish_at))
  end

  defp future?(%DateTime{} = at), do: DateTime.after?(at, DateTime.utc_now())
  defp future?(%NaiveDateTime{} = at), do: NaiveDateTime.after?(at, NaiveDateTime.utc_now())
  defp future?(_at), do: false

  @doc """
  The URL of `entry`'s Markdown version, with the host: its own URL with
  `.md` appended (`/index.md` for a site's root). `nil` when the entry has no
  URL.
  """
  @spec url(term()) :: String.t() | nil
  def url(entry) do
    case URL.resolve(entry, :with_host) do
      nil -> nil
      "" -> nil
      url -> markdown_url(url)
    end
  end

  @doc """
  `url` with `.md` appended to its path, keeping any query string.

      iex> Brando.SEO.Markdown.markdown_url("https://example.com/projects/sommerro/")
      "https://example.com/projects/sommerro.md"

      iex> Brando.SEO.Markdown.markdown_url("https://example.com/")
      "https://example.com/index.md"
  """
  @spec markdown_url(String.t()) :: String.t()
  def markdown_url(url) do
    uri = URI.parse(url)
    path = String.trim_trailing(uri.path || "", "/")
    path = if path == "", do: "/index", else: path
    URI.to_string(%{uri | path: path <> ".md"})
  end

  @doc """
  The Markdown document for `entry`: its title as a heading, then its block
  fields. Blocks are loaded when the entry does not have them preloaded.
  """
  @spec render(struct()) :: String.t()
  def render(%{__struct__: schema} = entry) do
    entry = load_blocks(entry)

    body =
      schema.__blocks_fields__()
      |> Enum.map(fn %{name: name} -> entry |> Map.get(:"entry_#{name}") |> Renderer.render(entry) end)
      |> Enum.reject(&(&1 == ""))

    [title_heading(entry) | body]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
    |> Kernel.<>("\n")
  end

  defp title_heading(entry) do
    case title(entry) do
      nil -> nil
      title -> Brando.Villain.Markdown.HTML.render([%MDEx.Heading{level: 1, nodes: [%MDEx.Text{literal: title}]}])
    end
  end

  @doc false
  def title(%{__struct__: schema} = entry) do
    [Map.get(entry, :title), meta_title(schema, entry), Map.get(entry, :meta_title)]
    |> Enum.find(&(is_binary(&1) and String.trim(&1) != ""))
    |> then(&(&1 && &1 |> Floki.parse_fragment!() |> Floki.text() |> String.trim()))
  end

  defp meta_title(schema, entry) do
    case Brando.Blueprint.Meta.extract_meta(schema, entry, only: ["title"]) do
      [{"title", title} | _] when is_binary(title) -> title
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp load_blocks(%{__struct__: schema} = entry) do
    loaded? =
      Enum.all?(schema.__blocks_fields__(), fn %{name: name} ->
        is_list(Map.get(entry, :"entry_#{name}"))
      end)

    if loaded?, do: entry, else: Brando.Repo.preload(entry, BlockPreloads.for_schema(schema), force: true)
  end
end
