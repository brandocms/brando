defmodule Brando.Images.Admin.ImageSeriesView do
  @moduledoc """
  View for the Brando Images module.
  """
  alias Brando.Images.ImageSeriesForm
  use Brando.AdminView, root: "templates"

  def render("upload_post.json", _assigns) do
    %{status: "200"}
  end

  def render("sort_post.json", _assigns) do
    %{status: "200"}
  end
end
