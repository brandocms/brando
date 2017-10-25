defmodule Brando.Images.ImageCategoryResolver do
  @moduledoc """
  Resolver for image categories
  """
  use Brando.Web, :resolver
  alias Brando.ImageCategory
  alias Brando.Images

  import Ecto.Query

  @doc """
  Get all categories
  """
  def all(_, %{context: %{current_user: _current_user}}) do
    Images.list_categories()
  end

  @doc """
  Get category
  """
  def find(%{category_id: category_id}, %{context: %{current_user: _current_user}}) do
    Images.get_category(category_id)
  end

  @doc """
  create image category
  """
  def create(%{image_category_params: image_category_params}, %{context: %{current_user: current_user}}) do
    Images.create_category(image_category_params, current_user)
    |> response
  end

  @doc """
  update image category
  """
  def update(%{image_category_id: image_category_id, image_category_params: image_category_params}, _) do
    Images.update_category(image_category_id, image_category_params)
    |> response
  end

  @doc """
  delete image category
  """
  def delete(%{image_category_id: image_category_id}, _) do
    Images.delete_category(image_category_id)
    |> response
  end
end
