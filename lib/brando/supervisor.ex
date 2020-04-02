defmodule Brando.Supervisor do
  @moduledoc """
  Main Brando supervisor.

  Looks after `Brando.Registry` and our cache.
  """
  use Supervisor

  @spec start_link :: :ignore | {:error, any} | {:ok, pid}
  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    children = [
      supervisor(Brando.Registry, []),
      worker(Cachex, [:cache, []])
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
