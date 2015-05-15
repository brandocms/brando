defmodule Brando.Menu.Admin do
  @moduledoc """
  Menu definitions for the Admin/dashboard Menu. See `Brando.Menu` docs for
  more information
  """
  use Brando.Menu

  menu "Admin",
    %{name: "Admin", anchor: "admin", icon: "fa fa-dashboard icon",
      submenu: [%{name: "Dashboard", url: {:admin_dashboard_path, :dashboard}},
                %{name: "Systeminfo", url: {:admin_dashboard_path, :system_info}, role: :superuser},
                %{name: "Logg ut", url: {:auth_path, :logout}}]}

end