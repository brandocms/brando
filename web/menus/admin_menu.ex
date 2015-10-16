defmodule Brando.Menu.Admin do
  @moduledoc """
  Menu definitions for the Admin/dashboard Menu. See `Brando.Menu` docs for
  more information
  """
  use Brando.Menu
  import Brando.Gettext

  menu gettext("Admin"),
    %{anchor: "admin", icon: "fa fa-dashboard icon",
      submenu: [
        %{name: gettext("Dashboard"), url: {:admin_dashboard_path, :dashboard}},
        %{name: gettext("System info"), url: {:admin_dashboard_path, :system_info},
          role: :superuser},
        %{name: gettext("Log out"), url: {:session_path, :logout}}]}
end
