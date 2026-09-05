defmodule Brando.Trait.Permalink do
  @moduledoc """
  Offers to create a permanent redirect when an existing entry's URL changes in
  the admin form. Add `trait :permalink` to a blueprint with an
  `absolute_url` definition to opt in.

  The form compares URLs after a successful save and only stores the redirect
  when the editor confirms it. Redirects belong to the entry's previous language.
  An exact redirect on the new URL is removed from the saved entry's language
  before the prompt, even if the editor continues without creating a redirect.
  """
  use Brando.Trait

  @doc """
  Builds a redirect proposal from the original and saved entries.

  Only local paths and HTTP(S) URLs with a usable path are supported. The source
  is matched as an exact path by the redirect service, including literal regex
  characters. Entries without a URL, new entries and unchanged URLs are ignored.
  """
  def redirect_for(previous, saved, default_language)

  def redirect_for(%{id: id, __struct__: schema} = previous, %{__struct__: schema} = saved, default_language)
      when not is_nil(id) do
    if schema.has_trait(__MODULE__) && Map.get(previous, :has_url, true) && Map.get(saved, :has_url, true) do
      previous = preload_url(previous, schema.__absolute_url_preloads__(), [])
      saved = preload_url(saved, schema.__absolute_url_preloads__(), force: true)

      with from when is_binary(from) <- usable_url(schema.__absolute_url__(previous)),
           to when is_binary(to) <- usable_url(schema.__absolute_url__(saved)),
           true <- from != to,
           from_path = URI.parse(from).path,
           true <- from_path != URI.parse(to).path do
        %{from: from_path, to: to, code: 301, language: to_string(Map.get(previous, :language) || default_language)}
      else
        _ -> nil
      end
    end
  end

  def redirect_for(_, _, _), do: nil

  defp preload_url(entry, [], _opts), do: entry
  defp preload_url(entry, preloads, opts), do: Brando.Repo.preload(entry, preloads, opts)

  defp usable_url(url) when is_binary(url) do
    case URI.parse(String.trim(url)) do
      %URI{scheme: scheme, host: host, path: "/" <> _ = path, query: nil, fragment: nil}
      when (is_nil(scheme) and is_nil(host)) or (scheme in ["http", "https"] and is_binary(host)) ->
        if !String.starts_with?(path, "//"), do: String.trim(url)

      _ ->
        nil
    end
  end

  defp usable_url(_), do: nil
end
