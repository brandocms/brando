defmodule Brando.System.Log do
  @moduledoc """
  Ephemeral system log.

  Used for start up deprecations et al
  """

  def warn(msg) do
    warnings = Brando.Cache.get(:warnings)
    IO.warn(msg, [])
    Brando.Cache.put(:warnings, [%{msg: msg} | warnings], :infinite)
  end
end
