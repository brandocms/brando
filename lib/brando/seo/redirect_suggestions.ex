defmodule Brando.SEO.RedirectSuggestions do
  @moduledoc """
  Pairs recorded 404s with the entry they most likely meant.

  A 404 whose last path segment matches an audited entry's slug is almost
  always a moved page — the slug survived, the section did not. Those get an
  `:exact` suggestion; a near miss on the slug (a typo, a dropped suffix) gets
  `:close`. URLs that already hit a redirect, and the noise every site's log
  collects (`wp-login.php`, `.env`, asset paths), are left out.
  """

  alias Brando.Sites.Redirects

  @type suggestion :: %{
          url: String.t(),
          hits: non_neg_integer(),
          to: String.t(),
          title: String.t() | nil,
          schema: module(),
          id: term(),
          confidence: :exact | :close
        }

  @close_threshold 0.9
  @noise_extensions ~w(.php .asp .aspx .env .git .xml .txt .json .js .css .map .ico .png .jpg .jpeg .gif .svg .webp .woff .woff2 .ttf .zip .sql .bak)
  @noise_prefixes ~w(/wp- /wordpress /xmlrpc /cgi-bin /.well-known /admin /api /media /static /assets /sitemaps)

  @doc """
  Suggests a destination for each 404 in `four_oh_fours` (as returned by
  `Brando.Sites.FourOhFour.list/0`) from the audited `rows`, sorted by hits.
  """
  @spec suggest([map()], [map()], String.t()) :: [suggestion()]
  def suggest(four_oh_fours, rows, language) do
    candidates =
      rows
      |> Enum.filter(&(is_binary(&1.url) and &1.url != ""))
      |> Enum.map(&{last_segment(&1.url), &1})
      |> Enum.reject(fn {segment, _} -> segment in [nil, ""] end)

    four_oh_fours
    |> Enum.reject(&(noise?(&1.url) or redirected?(&1.url, language)))
    |> Enum.flat_map(fn four_oh_four ->
      case best_match(last_segment(four_oh_four.url), candidates) do
        nil -> []
        {row, confidence} -> [suggestion(four_oh_four, row, confidence)]
      end
    end)
    |> Enum.sort_by(&{-&1.hits, &1.url})
  end

  @doc "Whether a recorded URL is the kind of probe no entry could satisfy."
  @spec noise?(String.t()) :: boolean()
  def noise?(url) when is_binary(url) do
    lower = String.downcase(url)

    Enum.any?(@noise_extensions, &String.ends_with?(lower, &1)) or
      Enum.any?(@noise_prefixes, &String.starts_with?(lower, &1))
  end

  def noise?(_), do: true

  defp best_match(nil, _candidates), do: nil
  defp best_match("", _candidates), do: nil

  defp best_match(segment, candidates) do
    case Enum.find(candidates, fn {candidate, _} -> candidate == segment end) do
      {_, row} ->
        {row, :exact}

      nil ->
        candidates
        |> Enum.map(fn {candidate, row} -> {String.jaro_distance(segment, candidate), row} end)
        |> Enum.filter(fn {distance, _} -> distance >= @close_threshold end)
        |> Enum.max_by(fn {distance, _} -> distance end, fn -> nil end)
        |> case do
          nil -> nil
          {_, row} -> {row, :close}
        end
    end
  end

  defp suggestion(four_oh_four, row, confidence) do
    %{
      url: four_oh_four.url,
      hits: four_oh_four.hits,
      to: row.url,
      title: row.title,
      schema: row.schema,
      id: row.id,
      confidence: confidence
    }
  end

  defp redirected?(url, language) do
    segments = url |> String.split("/", trim: true)
    match?({:ok, _}, Redirects.test_redirect(segments, language))
  rescue
    _ -> false
  end

  defp last_segment(url) when is_binary(url) do
    url
    |> URI.parse()
    |> Map.get(:path)
    |> Kernel.||("")
    |> String.split("/", trim: true)
    |> List.last()
    |> case do
      nil -> nil
      segment -> String.downcase(segment)
    end
  end

  defp last_segment(_), do: nil
end
