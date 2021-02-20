defmodule Brando.Revisions.RevisionResolver do
  @moduledoc """
  Resolver for Revisions
  """
  use Brando.Web, :resolver
  alias Brando.Revisions
  alias Brando.Villain

  @doc """
  Find revision
  """
  def find(%{entry_id: entry_id, entry_type: entry_type, revision: revision}, %{
        context: %{current_user: _current_user}
      }) do
    Revisions.get_revision()
  end

  @doc """
  Get all revisions
  """
  def all(args, %{context: %{current_user: _current_user}}) do
    Revisions.list_revisions(args)
  end

  @doc """
  Delete revision
  """
  def delete(%{revision_id: revision_id}, %{context: %{current_user: _current_user}}) do
    Revisions.delete_revision(revision_id)
  end
end
