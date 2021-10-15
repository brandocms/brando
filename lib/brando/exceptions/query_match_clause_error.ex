defmodule Brando.Exception.QueryMatchClauseError do
  @moduledoc """
  Defines an exception for missing `matches` clause.
  """
  defexception [:message]
end
