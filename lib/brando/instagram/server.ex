defmodule Brando.Instagram.Server do
  @moduledoc """
  GenServer for polling Instagram's API.

  See Brando.Instagram for instructions
  """

  use GenServer
  require Logger
  alias Brando.Instagram
  alias Brando.Instagram.API

  @doc false
  def start_link(server_name) do
    :gen_server.start({:local, server_name}, __MODULE__, [], [])
  end

  @doc false
  def init(_) do
    Process.flag(:trap_exit, true)
    :timer.send_after(5000, :poll)
    send(self(), :poll)
    {:ok, timer} = :timer.send_interval(Instagram.config(:interval), :poll)
    {:ok, {timer, :blank}}
  end

  @doc false
  def handle_info(:poll, {timer, filter}) do
    try do
      {:ok, filter} = API.fetch(filter)
    catch
      :exit, err ->
        Logger.error(inspect(err))
        Brando.SystemChannel.log(:error, "InstagramServer: Fanget :exit -> #{inspect(err)}")
    end
    {:noreply, {timer, filter}}
  end

  @doc false
  def terminate(:shutdown, {timer, _}) do
    :timer.cancel(timer)
    :ok
  end

  @doc false
  def terminate({%HTTPoison.Error{reason: :connect_timeout}, [_|_]}, {_, _}) do
    Brando.SystemChannel.log(:error, "InstagramServer: Tilkoblingen brukte for lang tid.")
    :ok
  end

  @doc false
  def terminate({%HTTPoison.Error{reason: :econnrefused}, [_|_]}, {_, _}) do
    Brando.SystemChannel.log(:error, "InstagramServer: Tilkoblingen ble nektet fra server.")
    :ok
  end

  @doc false
  def terminate({%HTTPoison.Error{reason: :nxdomain}, [_|_]}, {_, _}) do
    Brando.SystemChannel.log(:error, "InstagramServer: Kunne ikke koble til pga DNS problemer.")
    :ok
  end

  @doc false
  def terminate({%Postgrex.Error{message: "tcp connect: econnrefused", postgres: nil}, _}, _) do
    Brando.SystemChannel.log(:error, "InstagramServer: Postgres server nede.")
    :ok
  end
  @doc false
  def terminate(_reason, _state) do
    :ok
  end
end
