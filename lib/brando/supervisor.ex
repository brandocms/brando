defmodule Brando.Supervisor do
  @moduledoc """
  Main Brando supervisor.

  Looks after our cache.
  """
  use Supervisor

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    children = [
      %{id: :main_cache, start: {Cachex, :start_link, [:cache, []]}},
      %{id: :query_cache, start: {Cachex, :start_link, [:query, []]}},
      {Oban, oban_config()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp oban_config do
    Application.get_env(:brando, Oban) ||
      [
        repo: Brando.repo(),
        poll_interval: :timer.minutes(15),
        queues: [default: [limit: 1, poll_interval: :timer.minutes(15)]],
        plugins: [Oban.Plugins.Pruner],
        crontab: [
          # Generate a Sitemap every night at 02:00 UTC
          {"0 2 * * *", Brando.Worker.SitemapWorker},
          # Clean up soft deleted entries every night at 03:00 UTC
          {"6 13 * * *", Brando.Worker.SoftDeleteWorker}
        ]
      ]
  end
end
