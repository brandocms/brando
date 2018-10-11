defmodule Brando.Registry do
  @moduledoc """
  GenServer for registering extra modules
  """
  alias Brando.Exception.RegistryError
  require Logger

  defmodule State do
    @moduledoc """
    Struct for Registry server state.
    """
    defstruct gettext_modules: []
  end

  use GenServer

  # Public
  @doc false
  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(_) do
    Logger.info("==> Brando.Registry initialized")

    {:ok, %State{}}
  end

  def state do
    GenServer.call(__MODULE__, :state)
  end

  def register(module, opts \\ [:menu]) do
    unless Code.ensure_loaded?(Module.concat(module, "Gettext")) do
      raise RegistryError, message: "Could not find Gettext module for #{inspect(module)}"
    end

    GenServer.call(__MODULE__, {:register, module, opts})
  end

  def gettext_modules do
    state() |> Map.get(:gettext_modules) |> Enum.reverse()
  end

  def wipe do
    GenServer.call(__MODULE__, :wipe)
  end

  # Private
  @doc false
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  @doc false
  def handle_call(:wipe, _, _) do
    {:reply, %State{}, %State{}}
  end

  @doc false
  def handle_call({:register, module, opts}, _from, state) do
    state =
      if :gettext in opts,
        do: %State{
          state
          | gettext_modules: [Module.concat(module, "Gettext") | state.gettext_modules]
        },
        else: state

    {:reply, state, state}
  end
end
