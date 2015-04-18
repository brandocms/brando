defmodule Brando.Auth.LayoutView do
  @moduledoc """
  View for Brando's auth.
  Login/logout views use this.
  """
  use Brando.Web, :view # Brando.config(:templates_path)
  import Phoenix.Controller, only: [get_flash: 2]
end