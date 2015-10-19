defmodule Brando.Admin.ImageSeriesView do
  @moduledoc """
  View for the Brando Images module.
  """
  use Brando.Web, :view
  use Brando.Sequence, :view
  alias Brando.ImageSeriesForm
  alias Brando.ImageSeriesConfigForm
  import Brando.Gettext

  def render("upload_post.json", _assigns) do
    %{status: "200"}
  end
end
