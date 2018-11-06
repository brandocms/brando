defmodule Brando.Config do
  @moduledoc """
  GenServer for holding config
  """
  alias Brando.Exception.ConfigError
  require Logger

  @cfg_file "site_config.dat"

  defmodule State do
    @moduledoc """
    Struct for Registry server state.
    """
    defstruct site_config: %{}
  end

  use GenServer

  # Public
  @doc false
  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(_) do
    Logger.info("==> Brando.Config initialized")
    cfg = read_from_disk()
    {:ok, cfg}
  end

  def state do
    GenServer.call(__MODULE__, :state)
  end

  def register_key(key, val) do
    GenServer.call(__MODULE__, {:register, key, val})
  end

  def update_key(key, val) do
    GenServer.call(__MODULE__, {:update, key, val})
  end

  def get_site_config do
    state() |> Map.get(:site_config)
  end

  def get_site_config(key) do
    cfg = get_site_config()

    if key_map = Map.get(cfg, key) do
      Map.get(key_map, "value", nil)
    else
      nil
    end
  end

  def set_site_config(cfg) do
    GenServer.call(__MODULE__, {:set, cfg})
  end

  def read_from_disk do
    @cfg_file
    |> File.read!
    |> :erlang.binary_to_term([:safe])
  rescue
    _ ->
      %State{}
  end

  def write_to_disk(cfg) do
    insert = :erlang.term_to_binary(cfg, [minor_version: 2])
    case File.write(@cfg_file, insert) do
      :ok ->
        :ok

      err ->
        require Logger
        Logger.error "==> Brando.Config: Failed write_to_disk()"
        Logger.error inspect err
    end
  end

  # Private
  @doc false
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:set_state, new_state}, _from, _state) do
    {:reply, new_state, new_state}
  end

  def handle_call({:set, site_config}, _from, state) do
    state = put_in(state, [Access.key(:site_config)], site_config)
    write_to_disk(state)
    {:reply, state, state}
  end

  @doc false
  def handle_call({:register, key, val}, _from, state) do
    state = put_in(state, [Access.key(:site_config), Access.key(key)], val)

    {:reply, state, state}
  end

  @doc false
  def handle_call({:update, key, val}, _from, state) do
    state = put_in(state, [Access.key(:site_config), Access.key(key), Access.key("value")], val)

    {:reply, state, state}
  end
end
