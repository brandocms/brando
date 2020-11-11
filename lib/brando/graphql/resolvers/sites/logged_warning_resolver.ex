defmodule Brando.Sites.LoggedWarningResolver do
  @moduledoc """
  Resolver for logged warnings
  """
  use Brando.Web, :resolver

  @doc """
  Get all logged warnings
  """
  def all(_, %{context: %{current_user: _}}) do
    {:ok, Brando.Cache.get(:warnings)}
  end
end
