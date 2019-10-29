defmodule Brando.Config do
  @moduledoc """
  GenServer for holding config
  """
  defmodule State do
    @moduledoc """
    Struct for Registry server state.
    """
    defstruct site_config: %{}
  end

  # Public
  @doc false
  def start_link do
    raise(
      "Brando.Config is deprecated. Specify configuration data in `sites_identities` instead."
    )
  end
end
