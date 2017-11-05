defmodule Brando.Supervisor do
  @moduledoc """
  Main Brando supervisor.

  Looks after `Brando.Registry`.
  """
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    children = [
      supervisor(Brando.Registry, []),
    ]
    supervise(children, strategy: :one_for_one)
  end
end
