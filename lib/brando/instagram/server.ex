defmodule Brando.Instagram.Server do
  @moduledoc """
  GenServer for polling Instagram's API.

  See Brando.Instagram for instructions
  """
  use GenServer
  require Logger

  alias Brando.Instagram
  alias Brando.Instagram.API
  alias Brando.InstagramImage

  @doc false
  def start_link(server_name) do
    GenServer.start_link(__MODULE__, :ok, [name: server_name])
  end

  @doc false
  def init(_) do
    filter = InstagramImage.get_last_created_time()
    send(self(), :poll)
    {:ok, timer} = :timer.send_interval(Instagram.config(:interval), :poll)
    {:ok, {timer, filter, Instagram.config(:fetch)}}
  end

  @doc false
  def stop(server) do
    GenServer.call(server, :stop)
  end

  @doc false
  def handle_info(:poll, {timer, filter, cfg}) do
    try do
      {:ok, new_filter} = API.fetch(filter, cfg)
      {:noreply, {timer, new_filter, cfg}}
    catch
      :exit, err ->
        Logger.error(inspect(err))
        Brando.SystemChannel.log(:error, "InstagramServer: Fanget :exit -> " <>
                                         inspect(err))
        {:noreply, {timer, filter, cfg}}
    end
  end

  @doc false
  def handle_info({:EXIT, _, :normal}, state) do
    {:noreply, state}
  end

  @doc false
  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  @doc false
  def terminate(:shutdown, {timer, _}) do
    :timer.cancel(timer)
    :ok
  end

  @doc false
  def terminate({%HTTPoison.Error{reason: :connect_timeout}, [_|_]}, {_, _}) do
    Brando.SystemChannel.log(:error, "InstagramServer: " <>
                                     "Tilkoblingen brukte for lang tid.")
    :ok
  end

  @doc false
  def terminate({%HTTPoison.Error{reason: :econnrefused}, [_|_]}, {_, _}) do
    Brando.SystemChannel.log(:error, "InstagramServer: " <>
                                     "Tilkoblingen ble nektet fra server.")
    :ok
  end

  @doc false
  def terminate({%HTTPoison.Error{reason: :nxdomain}, [_|_]}, {_, _}) do
    Brando.SystemChannel.log(:error, "InstagramServer: " <>
                                     "Kunne ikke koble til pga DNS problemer.")
    :ok
  end

  @doc false
  def terminate({%Postgrex.Error{message: "tcp connect: econnrefused",
                                 postgres: nil}, _}, _) do
    Brando.SystemChannel.log(:error, "InstagramServer: Postgres server nede.")
    :ok
  end
  @doc false
  def terminate(_reason, _state) do
    :ok
  end
end
