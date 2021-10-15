defmodule Brando.Exception.QueryFilterClauseError do
  @moduledoc """
  Defines an exception for missing `filter` clause.
  """
  defexception [:message]
end
