defmodule Brando.SEO.Analytics.Plausible do
  @moduledoc """
  Visitors and pageviews per page from Plausible's Stats API (v2).

  Needs a Stats API key (Plausible → Account settings → API keys → New API
  key → Stats API) from the team that owns the site. See
  `Brando.SEO.Analytics` for configuration.
  """
  alias Brando.SEO.Analytics

  @base_url "https://plausible.io"

  @doc "Whether an API key and a site are configured."
  @spec configured?() :: boolean()
  def configured?, do: present?(config()[:api_key]) and present?(target())

  @doc "The Plausible site the figures are read for."
  @spec target() :: String.t() | nil
  def target, do: config()[:site_id] || Analytics.site_host()

  @doc "Visitors and pageviews per path over the last `days` days."
  @spec page_stats(pos_integer()) :: {:ok, %{String.t() => map()}} | {:error, String.t()}
  def page_stats(days) do
    today = Date.utc_today()

    body = %{
      site_id: target(),
      metrics: ["visitors", "pageviews"],
      date_range: [Date.to_iso8601(Date.add(today, -days)), Date.to_iso8601(Date.add(today, -1))],
      dimensions: ["event:page"],
      pagination: %{limit: 10_000}
    }

    case request(body) do
      {:ok, %Req.Response{status: 200, body: %{"results" => results}}} ->
        {:ok,
         Enum.reduce(results, %{}, fn %{"metrics" => [visitors, pageviews], "dimensions" => [page]}, acc ->
           # Paths that differ only by a trailing slash are one page to us.
           Map.update(
             acc,
             Analytics.path(page),
             %{visitors: visitors, pageviews: pageviews},
             &%{visitors: &1.visitors + visitors, pageviews: &1.pageviews + pageviews}
           )
         end)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{error_message(body)}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp request(body) do
    config = config()

    [
      url: String.trim_trailing(config[:base_url] || @base_url, "/") <> "/api/v2/query",
      json: body,
      auth: {:bearer, config[:api_key]},
      receive_timeout: 20_000,
      retry: false
    ]
    |> Keyword.merge(config[:req_options] || [])
    |> Req.post()
  end

  defp error_message(%{"error" => error}) when is_binary(error), do: error
  defp error_message(body) when is_binary(body) and body != "", do: String.slice(body, 0, 200)
  defp error_message(_), do: "no details"

  defp config, do: Analytics.source_config(:plausible)

  defp present?(value), do: is_binary(value) and value != ""
end
