defmodule Brando.Admin.Menu do
  use Brando.Menu
  alias Brando, as: B

  menu "Admin",
    %{name: "Admin", anchor: "admin", bgcolor: "#ffaaff", icon: "fa fa-dashboard icon",
      submenu: [%{name: "Dashboard", url: B.get_helpers().admin_dashboard_path(B.get_endpoint(), :dashboard)}]}

end