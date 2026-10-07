defmodule Brando.Trait.Meta do
  @moduledoc """
  Adds SEO metadata fields and exposes per-field AI defaults.

  Fields: `meta_title`, `meta_description`, `meta_image` and
  `meta_canonical_url`. The canonical URL overrides the address in the page's
  `<link rel="canonical">` and `og:url`, for content first published
  elsewhere or duplicated across entries. It must be an absolute `http(s)`
  URL; empty keeps the entry's own address.

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
        else: [meta_canonical_url: "must be a full address starting with https:// or http://"]
    end)
  end

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
