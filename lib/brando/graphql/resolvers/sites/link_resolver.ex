defmodule Brando.Sites.LinkResolver do
  @moduledoc """
  Resolver for links
  """
  use Brando.Web, :resolver
  alias Brando.Sites

  @doc """
  Get all links
  """
  def all(_, %{context: %{current_user: _}}) do
    Sites.list_links()
  end

  @doc """
  Get link by id
  """
  def get(%{link_id: link_id}, %{context: %{current_user: _}}) do
    Sites.get_link(link_id)
  end

  @doc """
  Create link
  """
  def create(%{link_params: link_params}, %{context: %{current_user: user}}) do
    Sites.create_link(link_params, user)
  end

  @doc """
  Update link
  """
  def update(%{link_id: link_id, link_params: link_params}, %{context: %{current_user: user}}) do
    Sites.update_link(link_id, link_params, user)
  end

  @doc """
  Delete link
  """
  def delete(%{link_id: link_id}, %{context: %{current_user: _}}) do
    Sites.delete_link(link_id)
  end
end
