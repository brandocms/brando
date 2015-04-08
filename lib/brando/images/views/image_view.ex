defmodule Brando.Images.Admin.ImageView do
  @moduledoc """
  View for the Brando Images module.
  """
  use Brando.AdminView, root: "templates"

  def render("delete_selected.json", assigns) do
    %{status: "200", ids: assigns[:ids]}
  end
end
