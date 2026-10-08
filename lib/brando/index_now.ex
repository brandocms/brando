defmodule Brando.IndexNow do
  @moduledoc """
  Tells search engines that take part in [IndexNow](https://www.indexnow.org)
  (Bing and the search engines and AI products that use its index, such as
  Copilot, DuckDuckGo and Yandex) when an entry's page appears, changes or
  goes away. Google does not take part.

  Off by default. Turn it on under Configuration → SEO; that also creates the
  site's key, which is served at `/<key>.txt` (`Brando.Plug.IndexNow`).

  ## What is submitted

  A content event subscriber (`Brando.ContentEvents`): the entry's URL is
  submitted when it is published, updated while published (or restored as
  published), unpublished or deleted. Each language version is an entry of
  its own, with its own URL, and is submitted when it changes. Entries
  without a URL of their own send nothing.

  The URLs are gathered for a minute (`batch_seconds`), in one scheduled
  `Brando.Worker.IndexNowSubmission` job per site environment, so a burst of
  saves is one request for each host, up to 10,000 URLs a request. The job
  runs on the `:webhooks` queue, with Brando's other outbound requests. The
  last submission and its answer are kept and shown under Configuration →
  SEO.

  Only the live environment submits: a staging copy of a site, or a copy
  made from a backup, never does. Without tenancy the deployment is the
  site; turn IndexNow off in its configuration on a server that is not:

      config :brando, Brando.IndexNow, enabled: false

  ## Configuration

      config :brando, Brando.IndexNow,
        enabled: true,
        batch_seconds: 60,
        endpoint: "https://api.indexnow.org/indexnow"

  Repeats are harmless: an event handled twice adds a URL the batch already
  has, or submits a URL again, which IndexNow takes as a hint, not an error.
  """
  @behaviour Brando.ContentEvents.Subscriber

  import Ecto.Query, only: [from: 2]

  alias Brando.ContentEvents.Event
  alias Brando.IndexNow.Settings
  alias Brando.Repo
  alias Brando.Tenant
  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Worker.IndexNowSubmission

  require Logger

  @endpoint "https://api.indexnow.org/indexnow"
  @batch_seconds 60
  @max_urls 10_000
  @response_limit 500
  @timeout 10_000

  @doc "Whether IndexNow can run at all in this deployment (see the moduledoc)."
  @spec available?() :: boolean()
  def available?, do: Keyword.get(config(), :enabled, true)

  @doc "How long a batch gathers URLs before it is sent, in seconds."
  @spec batch_seconds() :: non_neg_integer()
  def batch_seconds, do: Keyword.get(config(), :batch_seconds, @batch_seconds)

  @doc "Where submissions go."
  @spec endpoint() :: String.t()
  def endpoint, do: Keyword.get(config(), :endpoint, @endpoint)

  @doc "The most URLs one request carries."
  def max_urls, do: @max_urls

  defp config, do: Brando.config(__MODULE__) || []

  ## Settings

  @doc "The current environment's settings, or unsaved defaults when IndexNow was never turned on."
  @spec settings() :: Settings.t()
  def settings do
    Repo.one(from(s in Settings, order_by: [asc: s.id], limit: 1)) || %Settings{}
  rescue
    # An environment that has not run the `brando_211` migration
    error in Postgrex.Error ->
      Logger.warning("[Brando.IndexNow] Could not read the settings: " <> Exception.message(error))
      %Settings{}
  end

  @doc "Whether the current environment submits: turned on, available here, and live."
  @spec submits?(Settings.t()) :: boolean()
  def submits?(settings \\ settings()), do: settings.enabled and available?() and live_environment?()

  @doc "Turn IndexNow on, creating the key the first time."
  @spec enable() :: {:ok, Settings.t()} | {:error, Ecto.Changeset.t()}
  def enable, do: put_enabled(true)

  @doc "Turn IndexNow off. The key and the last submission are kept."
  @spec disable() :: {:ok, Settings.t()} | {:error, Ecto.Changeset.t()}
  def disable, do: put_enabled(false)

  defp put_enabled(enabled) do
    settings = settings()
    key = settings.key || generate_key()

    changeset = Settings.changeset(settings, %{enabled: enabled, key: key})
    if settings.id, do: Repo.update(changeset), else: Repo.insert(changeset)
  end

  @doc "A new key: 32 lowercase hexadecimal characters."
  @spec generate_key() :: String.t()
  def generate_key, do: 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

  @doc "The key file's URL on `host`'s site, `scheme://host[:port]/<key>.txt`."
  @spec key_location(URI.t(), String.t()) :: String.t()
  def key_location(%URI{} = uri, key),
    do: URI.to_string(%URI{scheme: uri.scheme, host: uri.host, port: uri.port, path: "/#{key}.txt"})

  @doc """
  Whether the current environment is its site's live one. Without tenancy
  there is only the one.
  """
  @spec live_environment?() :: boolean()
  def live_environment? do
    case Tenant.current_prefix() do
      "tenant_" <> rest ->
        case String.split(rest, "_", parts: 2) do
          [site, environment] -> match?(%{live: true}, Tenant.Cache.get_env(site, environment))
          _ -> false
        end

      _ ->
        true
    end
  end

  ## Content events

  # Events whose URL is worth telling search engines about: the page
  # appeared, changed, or went away.
  @impl Brando.ContentEvents.Subscriber
  def handle_event(%Event{url: url} = event) when is_binary(url) do
    if submit?(event) and submits?(), do: queue([url]), else: :ok
  end

  def handle_event(_event), do: :ok

  defp submit?(%Event{type: type}) when type in ["entry.published", "entry.unpublished", "entry.deleted"], do: true
  defp submit?(%Event{type: type, status: "published"}) when type in ["entry.updated", "entry.restored"], do: true
  defp submit?(_event), do: false

  @doc """
  Adds `urls` to the current environment's pending batch, or schedules a new
  one `batch_seconds/0` from now.
  """
  @spec queue([String.t()]) :: :ok | {:error, term()}
  def queue([]), do: :ok

  def queue(urls) do
    urls = Enum.uniq(urls)
    args = TenantJob.attach(%{"urls" => urls})

    case add_to_pending(args, urls) do
      :added ->
        :ok

      :none ->
        case Oban.insert(IndexNowSubmission.new(args, schedule_in: batch_seconds())) do
          {:ok, _job} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # One statement, so two saves at once cannot lose a URL.
  defp add_to_pending(args, urls) do
    fragment = Map.take(args, ["tenant_prefix"])

    query =
      from(j in Oban.Job,
        where:
          j.worker == ^inspect(IndexNowSubmission) and j.state == "scheduled" and
            fragment("? @> ?", j.args, ^fragment),
        update: [
          set: [
            args:
              fragment(
                "? || jsonb_build_object('urls', (SELECT coalesce(jsonb_agg(DISTINCT u), '[]'::jsonb) FROM jsonb_array_elements_text(coalesce(? -> 'urls', '[]'::jsonb) || to_jsonb(?::text[])) AS u))",
                j.args,
                j.args,
                type(^urls, {:array, :string})
              )
          ]
        ]
      )

    case Repo.update_all(query, [], Brando.ContentEvents.savepoint() ++ [prefix: "public"]) do
      {0, _} -> :none
      {_count, _} -> :added
    end
  end

  ## Submitting

  @doc """
  Submits `urls`: one request for each host, each with at most 10,000 URLs.
  Records the last request and its answer in the settings. Returns `:ok`, or
  `{:error, reason}` when a request should be tried again (no answer, `429`
  or a server error).
  """
  @spec submit([String.t()]) :: :ok | {:error, term()}
  def submit(urls) do
    settings = settings()

    if submits?(settings) and is_binary(settings.key) do
      urls
      |> Enum.uniq()
      |> Enum.group_by(&host_uri/1)
      |> Enum.reject(fn {uri, _} -> is_nil(uri) end)
      |> Enum.flat_map(fn {uri, host_urls} -> host_urls |> Enum.chunk_every(@max_urls) |> Enum.map(&{uri, &1}) end)
      |> Enum.reduce(:ok, fn {uri, chunk}, result ->
        case post(uri, chunk, settings.key) do
          :ok -> result
          error -> error
        end
      end)
    else
      :ok
    end
  end

  defp host_uri(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} = uri when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        %URI{scheme: scheme, host: host, port: uri.port}

      _ ->
        nil
    end
  end

  defp post(uri, urls, key) do
    body = %{host: uri.host, key: key, keyLocation: key_location(uri, key), urlList: urls}

    options =
      Keyword.merge(
        [json: body, receive_timeout: @timeout, connect_options: [timeout: @timeout], retry: false, redirect: false],
        Keyword.get(config(), :req_options, [])
      )

    case Req.post(endpoint(), options) do
      {:ok, %Req.Response{status: status, body: response}} ->
        record(status, response_text(status, response), length(urls))
        if status in [200, 202], do: :ok, else: retry_or_ok(status)

      {:error, error} ->
        message = Exception.message(error)
        record(nil, message, length(urls))
        {:error, message}
    end
  end

  # Too many requests and server errors pass; the rest are an answer about
  # the submission itself (a bad key, a URL from another host) that sending
  # it again would not change.
  defp retry_or_ok(status) when status == 429 or status >= 500, do: {:error, "IndexNow answered #{status}"}
  defp retry_or_ok(_status), do: :ok

  defp response_text(status, body) do
    text =
      case body do
        body when is_binary(body) -> String.trim(body)
        body when is_map(body) or is_list(body) -> Jason.encode!(body)
        _ -> ""
      end

    text = if text == "", do: Plug.Conn.Status.reason_phrase(status), else: text
    String.slice(text, 0, @response_limit)
  rescue
    _ -> ""
  end

  defp record(status, response, count) do
    settings = settings()

    if settings.id do
      settings
      |> Settings.changeset(%{
        last_submitted_at: DateTime.truncate(DateTime.utc_now(), :second),
        last_status: status,
        last_response: response,
        last_url_count: count
      })
      |> Repo.update()
    end
  end

  @doc "The key file's contents for `key`, when it is the current environment's key and IndexNow is on."
  @spec key_file(String.t()) :: String.t() | nil
  def key_file(key) do
    case settings() do
      %Settings{enabled: true, key: ^key} -> key
      _ -> nil
    end
  end
end
