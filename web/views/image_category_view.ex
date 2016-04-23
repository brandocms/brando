defmodule Brando.Admin.ImageCategoryView do
  @moduledoc """
  View for the Brando Images module.
  """
  use Brando.Web, :view
  use Brando.Sequence, :view
  alias Brando.ImageCategoryForm
  import Brando.Gettext

  def render("propagate_configuration.json", _) do
    %{status: 200}
  end
end
