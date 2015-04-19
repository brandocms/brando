defmodule Brando.Admin.ImageView do
  @moduledoc """
  View for the Brando Images module.
  """
  use Brando.Web, :view

  def render("delete_selected.json", assigns) do
    %{status: "200", ids: assigns[:ids]}
  end
end
