defmodule Brando.Session.LayoutView do
  @moduledoc """
  View for Brando's auth.

  Login/logout views use this.
  """
  use Brando.Web, :view
  import Phoenix.Controller, only: [get_flash: 2]
end
