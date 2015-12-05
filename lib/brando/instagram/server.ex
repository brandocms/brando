defmodule Brando.Instagram.Server do
  @moduledoc """
  GenServer for polling Instagram's API.

  See Brando.Instagram for instructions
  """
  use GenServer
  require Logger

  alias Brando.Instagram
  alias Brando.Instagram.AccessToken
  alias Brando.Instagram.API
  alias Brando.Instagram.Server.State
  alias Brando.InstagramImage


  # Public
  @doc false
  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc false
  def init(_) do
    token = if Instagram.config(:use_token), do: AccessToken.load_token()
    filter = InstagramImage.get_last_created_time()

    send(self(), :poll)
    {:ok, timer} = :timer.send_interval(Instagram.config(:interval), :poll)

    state =
      %State{}
      |> Map.put(:timer, timer)
      |> Map.put(:filter, filter)
      |> Map.put(:access_token, token)
      |> Map.put(:query, Instagram.config(:query))

    {:ok, state}
  end

  @doc false
  def stop(server) do
    GenServer.call(server, :stop)
  end

  @doc false
  def state(server) do
    GenServer.call(server, :state)
  end

  @doc false
  def refresh_token(server) do
    GenServer.call(server, :refresh_token)
  end

  # Private
  @doc false
  def handle_info(:poll, %State{} = state) do
    try do
      {:ok, new_filter} = API.query(state.filter, state.query)
      state = Map.put(state, :filter, new_filter)
      {:noreply, state}
    catch
      :exit, err ->
        Logger.error(inspect(err))
        {:noreply, state}
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
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  @doc false
  def handle_call(:refresh_token, _from, state) do
    Logger.error("% Refreshing token")
    {:noreply, state}
  end

  @doc false
  def terminate(:shutdown, {timer, _}) do
    :timer.cancel(timer)
    :ok
  end

  @doc false
  def terminate({%HTTPoison.Error{reason: :connect_timeout}, [_|_]}, {_, _}) do
    Logger.error("InstagramServer: connection timed out.")
  end

  @doc false
  def terminate({%HTTPoison.Error{reason: :econnrefused}, [_|_]}, {_, _}) do
    Logger.error("InstagramServer: connection refused.")
  end

  @doc false
  def terminate({%HTTPoison.Error{reason: :nxdomain}, [_|_]}, {_, _}) do
    Logger.error("InstagramServer: dns error, not found")
  end

  @doc false
  def terminate({%Postgrex.Error{message: "tcp connect: econnrefused",
                                 postgres: nil}, _}, _) do
    Logger.error("InstagramServer: postgrex connection refused")
  end

  @doc false
  def terminate(_reason, _state) do
    :ok
  end
end
