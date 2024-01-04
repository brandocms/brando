defmodule Brando.Exception.EntryNotFoundError do
  @moduledoc """
  Defines an exception for Configuration errors.
  """
  defexception message: "Entry not found", plug_status: 404
end
