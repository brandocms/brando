defmodule Brando.Sites.GlobalResolver do
  @moduledoc """
  Resolver for identitys
  """
  use Brando.Web, :resolver
  alias Brando.Sites

  @doc """
  Get global categories
  """
  def all(_, %{context: %{current_user: _}}) do
    Sites.list_global_categories()
  end

  @doc """
  Create category
  """
  def create(%{global_category_params: global_category_params}, %{context: %{current_user: _user}}) do
    Sites.create_global_category(global_category_params)
  end

  @doc """
  Update identity
  """
  def update(%{category_id: category_id, global_category_params: global_category_params}, %{
        context: %{current_user: _}
      }) do
    Sites.update_global_category(category_id, global_category_params)
  end

  @doc """
  Delete identity
  """
  def delete(_, %{context: %{current_user: _}}) do
    Sites.delete_identity()
  end
end
