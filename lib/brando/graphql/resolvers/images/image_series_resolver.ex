defmodule Brando.Images.ImageSeriesResolver do
  @moduledoc """
  Resolver for image series
  """
  use Brando.Web, :resolver
  alias Brando.Images

  @doc """
  Get series
  """
  def find(%{series_id: series_id}, %{context: %{current_user: _current_user}}) do
    Images.get_series(series_id)
  end

  @doc """
  create image series
  """
  def create(%{image_series_params: image_series_params}, %{context: %{current_user: current_user}}) do
    Images.create_series(image_series_params, current_user)
    |> response
  end

  @doc """
  update image series
  """
  def update(%{image_series_id: image_series_id, image_series_params: image_series_params}, _) do
    Images.update_series(image_series_id, image_series_params)
    |> response
  end

  @doc """
  delete image series
  """
  def delete(%{image_series_id: image_series_id}, _) do
    Images.delete_series(image_series_id)
    |> response
  end
end
