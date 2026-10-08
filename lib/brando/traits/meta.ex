defmodule Brando.Trait.Meta do
  @moduledoc """
  Adds SEO metadata fields and exposes per-field AI defaults.

  Fields: `meta_title`, `meta_description`, `meta_image` and
  `meta_canonical_url`. The canonical URL overrides the address in the page's
  `<link rel="canonical">` and `og:url`, for content first published
  elsewhere or duplicated across entries. It must be an absolute `http(s)`
  URL; empty keeps the entry's own address.

  `meta_nosnippet` and `meta_max_snippet` limit the text search engines and
  AI answers may quote from the page, written as the page's robots meta tag
  (`nosnippet`, `max-snippet:N`). They are what keeps a page's text out of
  Google's AI Overviews; `Google-Extended` in robots.txt does not.
  `meta_max_snippet` is a number of characters, `0` for none; empty leaves it
  to the search engine.

  It also adds `content_modified_at`, which `Brando.Trait.Meta.ContentModified`
  moves only on substantive edits. Read it through
  `Brando.Blueprint.Value.modified_at/1`.
  """
  use Brando.Trait

  alias Brando.Trait.Meta.Compiler
  alias Ecto.Changeset

  @meta_fields [:meta_title, :meta_description]

  @impl true
  def generate_code(module, config), do: Compiler.generate_code(module, config)

  @impl true
  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    changeset
    |> Changeset.update_change(:meta_canonical_url, &String.trim/1)
    |> Changeset.validate_change(:meta_canonical_url, fn :meta_canonical_url, url ->
      if absolute_http_url?(url),
        do: [],
        else: [meta_canonical_url: "must start with https://"]
    end)
    |> Changeset.validate_number(:meta_max_snippet, greater_than_or_equal_to: 0)
  end

  @doc """
  The robots meta directives for `entry`'s snippet settings, in the order
  they are written.

      iex> Brando.Trait.Meta.robots_directives(%{meta_nosnippet: true, meta_max_snippet: 50})
      ["nosnippet"]

      iex> Brando.Trait.Meta.robots_directives(%{meta_nosnippet: false, meta_max_snippet: 120})
      ["max-snippet:120"]

      iex> Brando.Trait.Meta.robots_directives(%{title: "No meta trait"})
      []
  """
  @spec robots_directives(map()) :: [String.t()]
  def robots_directives(%{meta_nosnippet: true}), do: ["nosnippet"]
  def robots_directives(%{meta_max_snippet: max}) when is_integer(max) and max >= 0, do: ["max-snippet:#{max}"]
  def robots_directives(_entry), do: []

  @doc """
  Whether `url` is an absolute `http`/`https` URL with a host.

      iex> Brando.Trait.Meta.absolute_http_url?("https://example.com/original")
      true

      iex> Brando.Trait.Meta.absolute_http_url?("/original")
      false
  """
  @spec absolute_http_url?(term()) :: boolean()
  def absolute_http_url?(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host}} when scheme in ["http", "https"] and is_binary(host) -> host != ""
      _ -> false
    end
  end

  def absolute_http_url?(_), do: false

  @impl true
  def ai_field_opts(_module, _config, field_name) when field_name not in @meta_fields, do: []

  def ai_field_opts(_module, config, field_name) do
    config
    |> Map.get(:ai, %{})
    |> get_value(field_name)
    |> normalize_ai_opts()
  end

  defp get_value(config, key) when is_map(config) do
    Map.get(config, key) || Map.get(config, Atom.to_string(key))
  end

  defp get_value(config, key) when is_list(config) do
    Keyword.get(config, key)
  end

  defp get_value(_, _), do: nil

  defp normalize_ai_opts(nil), do: []
  defp normalize_ai_opts(opts) when is_list(opts), do: opts
  defp normalize_ai_opts(opts) when is_map(opts), do: Enum.into(opts, [])
  defp normalize_ai_opts(_), do: []
end
