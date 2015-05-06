defmodule Brando.Instagram.Server do
  @moduledoc """
  Polls Instagram's API according to config's `interval` option.
  """
  use GenServer
  alias Brando.Instagram.API
  alias Brando.InstagramImage
  @cfg Application.get_env(:brando, Brando.Instagram)

  def start_link(server_name) do
    :gen_server.start_link({:local, server_name}, __MODULE__, [], [])
  end

  def init(_) do
    Process.flag(:trap_exit, true)
    {:ok, timer} = :timer.send_interval(@cfg[:interval], :poll)
    {:ok, {timer, InstagramImage.get_last_created_time}}
  end

  def handle_info(:poll, {timer, last_created_time}) do
    {:ok, last_created_time} = API.fetch(last_created_time)
    {:noreply, {timer, last_created_time}}
  end

  def terminate(:shutdown, {timer, _}) do
    :timer.cancel(timer)
    :ok
  end
end
