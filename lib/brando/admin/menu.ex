defmodule Brando.Admin.Menu do
  @moduledoc """
  Menu definitions for the Admin/dashboard Menu. See `Brando.Menu` docs for
  more information
  """
  use Brando.Menu
  alias Brando, as: B

  menu "Admin",
    %{name: "Admin", anchor: "admin", bgcolor: "#ffaaff", icon: "fa fa-dashboard icon",
      submenu: [%{name: "Dashboard", url: B.get_helpers().admin_dashboard_path(B.get_endpoint(), :dashboard)}]}

end