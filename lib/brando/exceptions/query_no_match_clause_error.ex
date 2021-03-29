defmodule Brando.Exception.NoMatchingQueryMatchClause do
  @moduledoc """
  Defines an exception for missing `matches` clause.
  """
  defexception [:message]
end
