defmodule Brando.Auth.LayoutView do
  @moduledoc """
  View for Brando's auth.
  Login/logout views use this.
  """
  use Brando.AdminView, root: Brando.config(:templates_path)
end