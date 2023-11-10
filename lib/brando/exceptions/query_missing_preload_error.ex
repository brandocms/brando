defmodule Brando.Exception.QueryMissingPreloadError do
  @moduledoc """
  Defines an exception for missing `preload`.
  """
  defexception [:message]
end
