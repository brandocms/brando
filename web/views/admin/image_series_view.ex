defmodule Brando.Admin.ImageSeriesView do
  @moduledoc """
  View for the Brando Images module.
  """
  use Brando.Web, :view
  use Brando.Sequence, :view
  alias Brando.ImageSeriesForm
  import Brando.Gettext

  def render("upload_post.json", %{status: 200}) do
    %{status: "200"}
  end

  def render("upload_post.json", %{status: 400, error_msg: error_msg}) do
    error_msg
  end
end
