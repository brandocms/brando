defmodule Brando.PopupForm.Registry do
  @moduledoc """
  GenServer for registering popup forms
  """
  require Logger

  defmodule State do
    @moduledoc """
    Struct for Registry server state.
    """
    defstruct forms: %{}
  end

  use GenServer

  # Public
  @doc false
  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(_) do
    Logger.info("==> Brando.PopupForm.Registry initialized")
    {:ok, %State{}}
  end

  def state do
    GenServer.call(__MODULE__, :state)
  end

  def register(key, name, form, header, wanted_fields) do
    GenServer.call(__MODULE__, {:register, key, name, form, header, wanted_fields})
  end

  @spec get(String.t) :: {:ok, atom, String.t, [atom]} | {:error, :not_registered}
  def get(key) do
    key = String.to_existing_atom(key)
    case Map.get(state().forms, key) do
      nil  -> {:error, :not_registered}
      data -> {:ok, data}
    end
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
  def handle_call({:register, key, name, form, header, wanted_fields}, _from, state) do
    state = put_in(state.forms, Map.put(state.forms, key, {name, form, header, wanted_fields}))
    {:reply, state, state}
  end
end
