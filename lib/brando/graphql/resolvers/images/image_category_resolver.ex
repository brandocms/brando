defmodule Brando.Images.ImageCategoryResolver do
  @moduledoc """
  Resolver for image categories
  """
  use Brando.Web, :resolver
  alias Brando.Images

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
    Images.get_image_category(%{matches: [id: category_id]})
  end

  @doc """
  create image category
  """
  def create(%{image_category_params: image_category_params}, %{
        context: %{current_user: current_user}
      }) do
    image_category_params
    |> Images.create_category(current_user)
  end

  @doc """
  update image category
  """
  def update(
        %{image_category_id: image_category_id, image_category_params: image_category_params},
        %{context: %{current_user: current_user}}
      ) do
    image_category_id
    |> Images.update_category(image_category_params, current_user)
  end

  @doc """
  delete image category
  """
  def delete(%{image_category_id: image_category_id}, _) do
    image_category_id
    |> Images.delete_category()
  end

  @doc """
  duplicate image category
  """
  def duplicate(%{image_category_id: image_category_id}, %{context: %{current_user: current_user}}) do
    image_category_id
    |> Images.duplicate_category(current_user)
  end
end
