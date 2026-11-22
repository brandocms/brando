defmodule Brando.Sites.Usage do
  @moduledoc """
  What each site of a multi-site installation uses: storage and traffic, one
  row per site per UTC day (`Brando.Sites.Usage.Day`), in the shared schema.

  Traffic is counted per node, in memory, as requests reach the endpoint on a
  site's own hosts (`Brando.Plug.Usage`), and flushed into the day's row on an
  interval and at shutdown (`Brando.Sites.Usage.Traffic`). Sizes come from a
  daily job that measures every site (`Brando.Worker.SiteUsage`), or one
  site when a superuser asks. Rows older than the retention period go with
  the daily job.

  Only with `tenancy_mode: :multi`: in the other modes nothing is counted,
  measured or shown.

      config :brando, Brando.Sites.Usage,
        retention_months: 13,
        flush_interval: :timer.seconds(60)

  These are operating figures, not invoices: a node that dies loses the
  counts since its last flush, and a flush whose commit was not confirmed is
  counted again by the next one.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Repo
  alias Brando.Sites.Site
  alias Brando.Sites.Usage.Day

  @public_opts [prefix: "public"]
  @topic "brando:site_usage"
  @measured_fields [:media_bytes, :builds_bytes, :databases, :measured_at]

  @doc "Whether usage is counted and shown: only with `tenancy_mode: :multi`."
  @spec enabled?() :: boolean()
  def enabled?, do: Brando.Tenant.mode() == :multi

  @doc "How many months of rows are kept (13 by default)."
  @spec retention_months() :: pos_integer()
  def retention_months, do: config(:retention_months, 13)

  @doc "How often each node writes its counters, in milliseconds (a minute by default)."
  @spec flush_interval() :: pos_integer()
  def flush_interval, do: config(:flush_interval, :timer.seconds(60))

  defp config(key, default), do: Application.get_env(:brando, __MODULE__, []) |> Keyword.get(key, default)

  @doc """
  Adds counted traffic, `[{site_id, day, requests, bytes}]`, to each day's
  row, creating it when there is none, and touches nothing else on it.
  Counts for a site that no longer exists are dropped.
  """
  @spec add_traffic([{pos_integer(), Date.t(), non_neg_integer(), non_neg_integer()}]) :: :ok
  def add_traffic([]), do: :ok

  def add_traffic(counts) do
    site_ids = counts |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    existing = MapSet.new(Repo.all(from(site in Site, where: site.id in ^site_ids, select: site.id), @public_opts))

    rows =
      for {site_id, day, requests, bytes} <- counts, MapSet.member?(existing, site_id),
          do: %{site_id: site_id, day: day, requests: requests, bytes_sent: bytes}

    add =
      from(day in Day,
        update: [
          set: [
            requests: fragment("? + EXCLUDED.requests", day.requests),
            bytes_sent: fragment("? + EXCLUDED.bytes_sent", day.bytes_sent)
          ]
        ]
      )

    Repo.insert_all(Day, rows, [on_conflict: add, conflict_target: [:site_id, :day]] ++ @public_opts)
    :ok
  end

  @doc """
  Stores a site's measurement on `day`'s row, creating it when there is
  none, and touches nothing else on it. When two measurements overlap, the
  last to finish wins.
  """
  @spec put_measurement(pos_integer(), Date.t(), map()) :: :ok
  def put_measurement(site_id, %Date{} = day, %{media_bytes: media, builds_bytes: builds, databases: databases}) do
    row = %{
      site_id: site_id,
      day: day,
      media_bytes: media,
      builds_bytes: builds,
      databases: databases,
      measured_at: DateTime.utc_now()
    }

    Repo.insert_all(
      Day,
      [row],
      [on_conflict: {:replace, @measured_fields}, conflict_target: [:site_id, :day]] ++ @public_opts
    )

    :ok
  end

  @doc "A site's rows for the `count` days up to `today`, oldest first."
  @spec days(Site.t(), Date.t(), pos_integer()) :: [Day.t()]
  def days(%Site{id: site_id}, %Date{} = today, count \\ 30) do
    first = Date.add(today, 1 - count)

    from(day in Day, where: day.site_id == ^site_id and day.day >= ^first and day.day <= ^today, order_by: day.day)
    |> Repo.all(@public_opts)
  end

  @doc """
  Per site id: the requests and bytes of the `count` days up to `today`, and
  its latest measurement (a `Brando.Sites.Usage.Day`, or nil), from any day.
  """
  @spec overview(Date.t(), pos_integer()) :: %{pos_integer() => map()}
  def overview(%Date{} = today, count \\ 30) do
    first = Date.add(today, 1 - count)

    traffic =
      from(day in Day,
        where: day.day >= ^first and day.day <= ^today,
        group_by: day.site_id,
        select:
          {day.site_id,
           %{
             requests: type(sum(day.requests), :integer),
             bytes_sent: type(sum(day.bytes_sent), :integer)
           }}
      )
      |> Repo.all(@public_opts)
      |> Map.new()

    measured =
      from(day in Day,
        where: not is_nil(day.measured_at),
        distinct: day.site_id,
        order_by: [asc: day.site_id, desc: day.day]
      )
      |> Repo.all(@public_opts)
      |> Map.new(&{&1.site_id, &1})

    (Map.keys(traffic) ++ Map.keys(measured))
    |> Enum.uniq()
    |> Map.new(fn site_id ->
      %{requests: requests, bytes_sent: bytes} = Map.get(traffic, site_id, %{requests: 0, bytes_sent: 0})
      {site_id, %{requests: requests, bytes_sent: bytes, measured: Map.get(measured, site_id)}}
    end)
  end

  @doc "Deletes the rows older than the retention period, counted back from `today`."
  @spec prune(Date.t()) :: non_neg_integer()
  def prune(%Date{} = today) do
    cutoff = Date.shift(today, month: -retention_months())
    {count, _} = Repo.delete_all(from(day in Day, where: day.day < ^cutoff), @public_opts)
    count
  end

  @doc "Subscribes the caller to measurements as they land: `{:site_usage_measured, site_id}`."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(Brando.pubsub(), @topic)

  @doc false
  def broadcast_measured(site_id),
    do: Phoenix.PubSub.broadcast(Brando.pubsub(), @topic, {:site_usage_measured, site_id})
end
