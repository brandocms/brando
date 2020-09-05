defmodule Brando.Supervisor do
  @moduledoc """
  Main Brando supervisor.

  Looks after `Brando.Registry` and our cache.
  """
  use Supervisor

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    children = [
      supervisor(Brando.Registry, []),
      worker(Cachex, [:cache, []]),
      {Oban, oban_config()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp oban_config do
    [
      repo: Brando.repo(),
      plugins: [Oban.Plugins.Pruner],
      queues: [default: 10],
      crontab: [
        # Generate a Sitemap every night at 02:00
        {"0 2 * * *", Brando.Worker.SitemapWorker}
      ]
    ]
  end
end
