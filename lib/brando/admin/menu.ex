defmodule Brando.Admin.Menu do
  @moduledoc """
  Menu definitions for the Admin/dashboard Menu. See `Brando.Menu` docs for
  more information
  """
  use Brando.Menu

  menu "Admin",
    %{name: "Admin", anchor: "admin", bgcolor: "#ffaaff", icon: "fa fa-dashboard icon",
      submenu: [%{name: "Dashboard", url: {:admin_dashboard_path, :dashboard}}]}

end