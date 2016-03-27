defmodule Brando.Registry do
  @moduledoc """
  GenServer for registering extra modules
  """
  defmodule State do
    @moduledoc """
    Struct for Registry server state.
    """
    defstruct menu_modules: [],
              gettext_modules: []
  end

  use GenServer
  require Logger

  @default_modules [Brando.Images, Brando.Users, Brando.Admin]

  # Public
  @doc false
  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(_) do
    modules = for m <- @default_modules do
      Module.concat(m, "Menu")
    end
    {:ok, %State{menu_modules: modules}}
  end

  def state do
    GenServer.call(__MODULE__, :state)
  end

  def register(module, opts \\ [:gettext, :menu]) do
    if :menu in opts do
      unless Code.ensure_loaded?(Module.concat(module, "Menu")) do
        raise "Could not find Menu module for #{inspect module}"
      end
    end

    if :gettext in opts do
      unless Code.ensure_loaded?(Module.concat(module, "Gettext")) do
        raise "Could not find Gettext module for #{inspect module}"
      end
    end

    GenServer.call(__MODULE__, {:register, module, opts})
  end

  def gettext_modules do
    state() |> Map.get(:gettext_modules) |> Enum.reverse
  end

  def menu_modules do
    state() |> Map.get(:menu_modules) |> Enum.reverse
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
    state = if :menu in opts, do:
      %State{state | menu_modules: [Module.concat(module, "Menu")|state.menu_modules]}

    state = if :gettext in opts do
      %State{state | gettext_modules: [Module.concat(module, "Gettext")|state.gettext_modules]}
    else
      state
    end

    {:reply, state, state}
  end
end
