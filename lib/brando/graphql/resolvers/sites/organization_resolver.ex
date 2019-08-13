defmodule Brando.Sites.OrganizationResolver do
  @moduledoc """
  Resolver for organizations
  """
  use Brando.Web, :resolver
  alias Brando.Sites

  @doc """
  Get organization by id
  """
  def get(_, %{context: %{current_user: _}}) do
    Sites.get_organization()
  end

  @doc """
  Create organization
  """
  def create(%{organization_params: organization_params}, %{context: %{current_user: user}}) do
    Sites.create_organization(organization_params, user)
  end

  @doc """
  Update organization
  """
  def update(%{organization_params: organization_params}, %{
        context: %{current_user: user}
      }) do
    Sites.update_organization(organization_params, user)
  end

  @doc """
  Delete organization
  """
  def delete(_, %{context: %{current_user: _}}) do
    Sites.delete_organization()
  end
end
