defmodule Brando.Sites.GlobalResolver do
  @moduledoc """
  Resolver for identitys
  """
  use BrandoAdmin, :resolver
  alias Brando.Globals

  @doc """
  Get global categories
  """
  def all(_, %{context: %{current_user: _}}) do
    Globals.list_global_categories()
  end

  @doc """
  Create category
  """
  def create(%{global_category_params: global_category_params}, %{context: %{current_user: _user}}) do
    Globals.create_global_category(global_category_params)
  end

  @doc """
  Update category
  """
  def update(%{category_id: category_id, global_category_params: global_category_params}, %{
        context: %{current_user: _}
      }) do
    Globals.update_global_category(category_id, global_category_params)
  end
end
