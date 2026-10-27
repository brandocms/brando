defmodule Brando.Sites.FourOhFour do
  @buffer_limit 1000

  @moduledoc """
  The 404 log: which missing URLs are requested, how often and from where.

  Hits are counted per URL, referrer and day in a small in-memory buffer (the
  `:four_oh_four` Cachex cache), and `flush/0` adds the counts to
  `sites_not_found_hits` with one upsert per tenant. `Brando.Sites.FourOhFour.Flusher`
  flushes every minute and when the node shuts down, so a burst of requests for
  missing pages costs one statement a minute rather than one per request, and
  the log survives deploys. The buffer holds at most #{@buffer_limit} keys between
  flushes; past that, the least recently counted are dropped.

  Rows older than `retention_days/0` are deleted nightly by
  `Brando.Worker.NotFoundPurger`.

      config :brando, Brando.Sites.FourOhFour,
        flush_interval: :timer.seconds(60),
        retention_days: 90

  `flush_interval: false` turns the periodic flush off (the test config does);
  `list/0` still flushes before it reads.
  """
  import Ecto.Query, only: [from: 2]

  require Cachex.Spec
  require Logger

  alias Brando.Sites.NotFoundHit

  @cache :four_oh_four
  @default_flush_interval :timer.seconds(60)
  @default_retention_days 90
  @list_limit 500
  @max_url_length 1000
  @max_referrer_length 500

  @doc "The longest URL logged; a longer one is logged cut to this length."
  def max_url_length, do: @max_url_length

  @doc "How many URL, referrer and day counts the buffer holds between flushes."
  def buffer_limit, do: @buffer_limit

  @doc "Counts a 404 for `conn`'s path, with its referrer."
  @spec add_404(Plug.Conn.t()) :: Plug.Conn.t()
  def add_404(conn) do
    path = Path.join(["/" | conn.path_info])
    url = String.slice(path, 0, @max_url_length)
    key = Brando.Tenant.cache_key({url, referrer(conn, path, url), Date.utc_today()})
    Cachex.incr(@cache, key, 1)
    conn
  end

  # Scheme, host and path of an http(s) referrer, without its query string,
  # which would split one link's hits across rows and can carry tokens. A
  # self-referrer is stored with the logged URL as its path, so `list/0`
  # recognises it however long the path.
  defp referrer(conn, path, url) do
    with [value | _] <- Plug.Conn.get_req_header(conn, "referer"),
         %URI{scheme: scheme, host: host} = uri when scheme in ["http", "https"] and is_binary(host) <- URI.parse(value) do
      uri = %URI{uri | query: nil, fragment: nil, userinfo: nil}

      if self_referrer?(path, URI.to_string(uri)) do
        cut_bytes(URI.to_string(%URI{uri | path: nil}), @max_referrer_length) <> url
      else
        uri |> URI.to_string() |> String.slice(0, @max_referrer_length)
      end
    else
      _ -> ""
    end
  end

  # At most `max` bytes, the unique index's limit being in bytes, without a
  # split character at the end.
  defp cut_bytes(string, max) when byte_size(string) <= max, do: string
  defp cut_bytes(string, max), do: string |> binary_part(0, max) |> drop_split_character(3)

  defp drop_split_character(string, 0), do: string

  defp drop_split_character(string, bytes) do
    if String.valid?(string),
      do: string,
      else: string |> binary_part(0, byte_size(string) - 1) |> drop_split_character(bytes - 1)
  end

  @doc """
  Adds the buffered counts to the database, for every tenant. Returns the
  number of rows written. A count is taken out of the buffer before it is
  written, so concurrent flushes never write it twice.
  """
  @spec flush() :: non_neg_integer()
  def flush do
    @cache
    |> Cachex.stream!()
    |> Enum.to_list()
    |> Enum.flat_map(&take_entry/1)
    |> Enum.group_by(fn {prefix, _row} -> prefix end, fn {_prefix, row} -> row end)
    |> Enum.map(fn {prefix, rows} -> upsert(prefix, rows) end)
    |> Enum.sum()
  end

  defp take_entry(Cachex.Spec.entry(key: key, modified: modified)) do
    with {prefix, {url, referrer, date}} <- unwrap(key),
         {:ok, hits} when is_integer(hits) and hits > 0 <- Cachex.take(@cache, key) do
      last_hit_at = modified |> DateTime.from_unix!(:millisecond) |> DateTime.truncate(:second)
      [{prefix, %{url: url, referrer: referrer, date: date, hits: hits, last_hit_at: last_hit_at}}]
    else
      _ -> []
    end
  end

  defp unwrap({:tenant, prefix, key}), do: {prefix, key}
  defp unwrap(key), do: {nil, key}

  defp upsert(prefix, rows) do
    on_conflict =
      from h in NotFoundHit,
        update: [
          set: [
            hits: fragment("? + EXCLUDED.hits", h.hits),
            last_hit_at: fragment("GREATEST(?, EXCLUDED.last_hit_at)", h.last_hit_at)
          ]
        ]

    opts = [on_conflict: on_conflict, conflict_target: [:url, :referrer, :date]]
    opts = if prefix, do: Keyword.put(opts, :prefix, prefix), else: opts

    rows
    |> Enum.chunk_every(1000)
    |> Enum.map(&(NotFoundHit |> Brando.Repo.insert_all(&1, opts) |> elem(0)))
    |> Enum.sum()
  rescue
    error in [Postgrex.Error, DBConnection.ConnectionError] ->
      Logger.warning("==> 404 log: could not store #{length(rows)} rows: #{Exception.message(error)}")
      0
  end

  @doc """
  The missing URLs recorded in the current tenant, most requested first, with
  their total hits, when they were last requested (formatted), the referrer
  that sent most of them and whether they are a scanner's probe. Flushes the
  buffer first.

  A self-referrer (see `self_referrer?/2`) is never the named referrer. A URL
  is a probe when its path is one (`probe?/1`), or when more than half its
  hits name the URL itself as their referrer, as scanners do.
  """
  @spec list() :: [
          %{url: String.t(), hits: integer(), last_hit_at: String.t(), referrer: String.t() | nil, probe: boolean()}
        ]
  def list do
    flush()

    totals =
      Brando.Repo.all(
        from h in NotFoundHit,
          group_by: h.url,
          select: %{url: h.url, hits: sum(h.hits), last_hit_at: max(h.last_hit_at)},
          order_by: [desc: sum(h.hits), asc: h.url],
          limit: @list_limit
      )

    referrers = referrer_hits(Enum.map(totals, & &1.url))

    Enum.map(totals, fn total ->
      {self_referred, others} =
        referrers |> Map.get(total.url, []) |> Enum.split_with(&self_referrer?(total.url, elem(&1, 0)))

      self_hits = self_referred |> Enum.map(&elem(&1, 1)) |> Enum.sum()

      %{
        url: total.url,
        hits: total.hits,
        last_hit_at: Brando.Utils.Datetime.format_datetime(total.last_hit_at, "%d/%m/%y, %H:%M"),
        referrer: others |> Enum.max_by(&elem(&1, 1), fn -> {nil, 0} end) |> elem(0),
        probe: probe?(total.url) or self_hits * 2 > total.hits
      }
    end)
  end

  defp referrer_hits([]), do: %{}

  defp referrer_hits(urls) do
    from(h in NotFoundHit,
      where: h.url in ^urls and h.referrer != "",
      group_by: [h.url, h.referrer],
      select: {h.url, h.referrer, sum(h.hits)}
    )
    |> Brando.Repo.all()
    |> Enum.group_by(&elem(&1, 0), &{elem(&1, 1), elem(&1, 2)})
  end

  @doc """
  Whether `referrer` is the missing `url` itself, whatever its scheme, host,
  query or trailing slash. Scanners send the URL they probe as its referrer; a
  visitor never arrives at a missing page from that page.
  """
  @spec self_referrer?(String.t(), String.t()) :: boolean()
  def self_referrer?(url, referrer) when is_binary(url) and is_binary(referrer) do
    case URI.parse(referrer) do
      %URI{host: host, path: path} when is_binary(host) -> same_path?(decode(path || ""), decode(url))
      _ -> false
    end
  end

  defp same_path?(a, b), do: String.trim_trailing(a, "/") == String.trim_trailing(b, "/")

  # A path cut mid-escape, or with a lone %, is compared as it is.
  defp decode(path) do
    URI.decode(path)
  rescue
    ArgumentError -> path
  end

  @doc "Forgets a recorded URL, e.g. once a redirect covers it."
  @spec remove(String.t()) :: :ok
  def remove(url) when is_binary(url) do
    prefix = Brando.Tenant.current_prefix()

    @cache
    |> Cachex.stream!(Cachex.Query.build(output: :key))
    |> Enum.filter(&match?({^prefix, {^url, _referrer, _date}}, unwrap(&1)))
    |> Enum.each(&Cachex.del(@cache, &1))

    Brando.Repo.delete_all(from h in NotFoundHit, where: h.url == ^url)
    :ok
  end

  @doc "Deletes the current tenant's rows older than `days`. Returns how many."
  @spec purge(non_neg_integer()) :: non_neg_integer()
  def purge(days \\ retention_days()) do
    cutoff = Date.add(Date.utc_today(), -days)
    {count, _} = Brando.Repo.delete_all(from h in NotFoundHit, where: h.date < ^cutoff)
    count
  end

  @doc "How many days of 404s are kept (default #{@default_retention_days})."
  @spec retention_days() :: pos_integer()
  def retention_days, do: Keyword.get(config(), :retention_days, @default_retention_days)

  @doc "How often the buffer is flushed, in milliseconds, or `false`."
  @spec flush_interval() :: pos_integer() | false
  def flush_interval, do: Keyword.get(config(), :flush_interval, @default_flush_interval)

  defp config, do: Application.get_env(:brando, __MODULE__, [])

  # Requests no real visitor or broken link makes: scanners looking for
  # WordPress, PHP shells, exposed config, credentials, source maps and dev
  # servers. They're kept, but the SEO view folds them away so the 404s worth
  # a redirect stand out. Generic words scanners also try (/login, /team,
  # /dashboard) are real pages on many sites, so they're left to the
  # self-referrer rule in `list/0`.
  @probe_patterns [
    # PHP scripts and their editor/backup copies: x.php, x.php~, x.php.bak
    ~r/\.php\d?(?:[.~]|$)/i,
    # Dotfiles and dot-directories (.env, .git/, .ssh/, .aws/, .htaccess),
    # except .well-known/, which real services use
    ~r{(?:^|/)\.(?!well-known/)[^/]},
    ~r{(?:^|/)wp-|wordpress}i,
    ~r{phpunit|eval-stdin|/vendor/|^/cgi-bin/|^/containers/json$}i,
    ~r{(?:^|/)(?:config|secrets|credentials)\.(?:json|ya?ml|php|ini)$}i,
    # Source maps (x.js.map, x.astro.mjs.map), keys, dumps and env files
    ~r/\.(?:map|pem|key|env|sql(?:\.(?:gz|zip))?)$/i,
    # Dev servers, debug consoles and file reads, /proc/self/ also after ../
    ~r{(?:^|/)(?:@fs/|proc/self/|__vite|_profiler(?:/|$)|phpmyadmin[\d.-]*(?:/|$)|server-status$)|^/actuator(?:/|$)}i,
    ~r{laravel\.log|storage/logs/|(?:^|/)id_(?:rsa|dsa|ecdsa|ed25519)(?:\.pub)?$}i,
    # Deploy, container and cloud config
    ~r{(?:^|/)(?:docker-compose(?:\.[\w-]+)?\.ya?ml|dockerfile|composer\.(?:json|lock)|appsettings(?:\.\w+)?\.json|application(?:-[\w-]+)?\.(?:ya?ml|properties)|service-account\.json|vercel\.json|netlify\.toml|wrangler\.toml|railway\.json|values\.ya?ml|rclone\.conf|aws-exports\.js|env\.js)$}i,
    ~r{(?:^|/)(?:supabase/config\.toml|config/aws\.ya?ml)$}i
  ]

  @doc """
  Whether a 404'd path looks like a vulnerability scanner's probe rather than
  a moved page or a broken link. `list/0` also counts a URL mostly requested
  with itself as the referrer as a probe.
  """
  @spec probe?(String.t()) :: boolean()
  def probe?(url) when is_binary(url) do
    path = url |> URI.parse() |> Map.get(:path) |> Kernel.||("") |> decode()
    Enum.any?(@probe_patterns, &Regex.match?(&1, path))
  end
end
