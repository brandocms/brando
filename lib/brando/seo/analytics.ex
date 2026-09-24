defmodule Brando.SEO.Analytics do
  @moduledoc """
  Traffic and search figures per page, for the Content SEO tab.

  Two optional sources, each enabled by configuring it:

    * **Plausible** — visitors and pageviews per page
      (`Brando.SEO.Analytics.Plausible`)
    * **Google Search Console** — clicks, impressions, click-through rate and
      average position per page, and the searches a page is shown for
      (`Brando.SEO.Analytics.SearchConsole`)

  ## Configuration

      config :brando, Brando.SEO.Analytics,
        period_days: 28,
        plausible: [
          api_key: System.get_env("PLAUSIBLE_API_KEY"),
          # Defaults to the host of the SEO settings' base URL
          site_id: "example.com",
          base_url: "https://plausible.io"
        ],
        search_console: [
          # The service account's JSON key, or a path to the file
          credentials: System.get_env("GOOGLE_SEARCH_CONSOLE_CREDENTIALS"),
          # Defaults to "sc-domain:" plus the host of the SEO base URL
          property: "sc-domain:example.com"
        ]

  Leaving `site_id` and `property` out lets one key serve every site of a
  multi-tenant install: each tenant's own SEO base URL names its site.

  Figures are keyed by URL path and cached per tenant for an hour, so running
  the audit again does not spend the APIs' quotas. A source that fails is
  reported alongside the figures rather than failing the audit.
  """
  alias Brando.SEO.Analytics.Plausible
  alias Brando.SEO.Analytics.SearchConsole

  @period_days 28
  @ttl :timer.hours(1)

  @type source :: :plausible | :search_console
  @type page :: %{
          optional(:visitors) => non_neg_integer(),
          optional(:pageviews) => non_neg_integer(),
          optional(:clicks) => non_neg_integer(),
          optional(:impressions) => non_neg_integer(),
          optional(:ctr) => float(),
          optional(:position) => float(),
          optional(:url) => String.t()
        }
  @type t :: %{
          sources: [%{source: source(), target: String.t()}],
          errors: [{source(), String.t()}],
          pages: %{String.t() => page()},
          period_days: pos_integer()
        }

  @doc "The configured sources and what each reads, for display."
  @spec sources() :: [%{source: source(), target: String.t()}]
  def sources do
    [plausible: Plausible, search_console: SearchConsole]
    |> Enum.filter(fn {_source, module} -> module.configured?() end)
    |> Enum.map(fn {source, module} -> %{source: source, target: module.target()} end)
  end

  @doc "Whether any source is configured."
  @spec configured?() :: boolean()
  def configured?, do: sources() != []

  @doc "Days the figures cover."
  @spec period_days() :: pos_integer()
  def period_days, do: Keyword.get(config(), :period_days, @period_days)

  @doc """
  Figures for every page the sources know of, merged by path.

  ## Options

    * `:refresh` — skip the cache and read the sources again
  """
  @spec page_stats(keyword()) :: t()
  def page_stats(opts \\ []) do
    days = period_days()
    key = {:seo_analytics, days}

    case !opts[:refresh] && Brando.Cache.get(key) do
      %{pages: _} = cached ->
        cached

      _ ->
        stats = fetch(days)
        # A failed read is not worth keeping for an hour.
        if stats.errors == [], do: Brando.Cache.put(key, stats, @ttl)
        stats
    end
  end

  @doc """
  The searches `page` is shown for in Google, most impressions first.
  `page` is the page's figures from `page_stats/1` or its URL.
  """
  @spec top_queries(page() | String.t(), keyword()) :: {:ok, [map()]} | {:error, String.t()} | :not_configured
  def top_queries(page, opts \\ [])
  def top_queries(%{url: url}, opts), do: top_queries(url, opts)

  def top_queries(url, opts) when is_binary(url) do
    if SearchConsole.configured?() do
      days = period_days()
      key = {:seo_analytics_queries, days, url}

      case !opts[:refresh] && Brando.Cache.get(key) do
        queries when is_list(queries) ->
          {:ok, queries}

        _ ->
          with {:ok, queries} <- SearchConsole.top_queries(absolute(url), days, Keyword.get(opts, :limit, 10)) do
            Brando.Cache.put(key, queries, @ttl)
            {:ok, queries}
          end
      end
    else
      :not_configured
    end
  end

  def top_queries(_page, _opts), do: :not_configured

  @doc """
  The path figures are keyed by: no host, no query string, and no trailing
  slash except on the root.
  """
  @spec path(String.t() | nil) :: String.t() | nil
  def path(nil), do: nil

  def path(url) do
    path = URI.parse(url).path || "/"

    case String.trim_trailing(path, "/") do
      "" -> "/"
      path -> path
    end
  end

  @doc "The host of the current tenant's SEO base URL, which sources default to."
  @spec site_host() :: String.t() | nil
  def site_host do
    with language when not is_nil(language) <- Brando.config(:default_language),
         %{base_url: base_url} when is_binary(base_url) and base_url != "" <-
           Brando.Cache.SEO.get(to_string(language)),
         %URI{host: host} when is_binary(host) <- URI.parse(base_url) do
      host
    else
      _ -> nil
    end
  end

  @doc false
  def config, do: Application.get_env(:brando, __MODULE__, [])

  @doc false
  def source_config(source), do: Keyword.get(config(), source, [])

  defp fetch(days) do
    sources = sources()

    results =
      Enum.map(sources, fn %{source: source} ->
        module = if source == :plausible, do: Plausible, else: SearchConsole
        {source, module.page_stats(days)}
      end)

    %{
      sources: sources,
      period_days: days,
      errors: for({source, {:error, message}} <- results, do: {source, message}),
      pages:
        Enum.reduce(results, %{}, fn
          {_source, {:ok, pages}}, acc -> Map.merge(acc, pages, fn _path, a, b -> Map.merge(a, b) end)
          _, acc -> acc
        end)
    }
  end

  # Search Console knows pages by their full URL; entries may give a path.
  defp absolute("http" <> _ = url), do: url

  defp absolute(path) do
    case site_host() do
      nil -> path
      host -> "https://" <> host <> path
    end
  end
end
