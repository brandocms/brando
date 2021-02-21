defmodule Brando.Revisions.RevisionResolver do
  @moduledoc """
  Resolver for Revisions
  """
  use Brando.Web, :resolver
  alias Brando.Revisions

  @doc """
  Get all revisions
  """
  def all(args, _) do
    Revisions.list_revisions(args)
  end
end
