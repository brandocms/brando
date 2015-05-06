defmodule Brando.Instagram.Server do
  @moduledoc """
  Polls Instagram's API according to config's `interval` option.
  """
  use GenServer
  alias Brando.Instagram.API
  @cfg Application.get_env(:brando, Brando.Instagram)

  def start_link(server_name) do
    :gen_server.start_link({:local, server_name}, __MODULE__, [], [])
  end

  def init(_) do
    Process.flag(:trap_exit, true)
    {:ok, timer} = :timer.send_interval(@cfg[:interval], :poll)
    {:ok, {timer, :blank}}
  end

  def handle_info(:poll, {timer, filter}) do
    {:ok, filter} = API.fetch(filter)
    {:noreply, {timer, filter}}
  end

  def terminate(:shutdown, {timer, _}) do
    :timer.cancel(timer)
    :ok
  end
end
