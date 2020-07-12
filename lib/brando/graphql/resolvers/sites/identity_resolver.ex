defmodule Brando.Sites.IdentityResolver do
  @moduledoc """
  Resolver for identitys
  """
  use Brando.Web, :resolver
  alias Brando.Sites

  @doc """
  Get identity by id
  """
  def get(_, %{context: %{current_user: _}}) do
    Sites.get_identity()
  end

  @doc """
  Create identity
  """
  def create(%{identity_params: identity_params}, %{context: %{current_user: user}}) do
    Sites.create_identity(identity_params, user)
  end

  @doc """
  Update identity
  """
  def update(%{identity_params: identity_params}, %{
        context: %{current_user: user}
      }) do
    Sites.update_identity(identity_params, user)
  end
end
