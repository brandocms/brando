defmodule Brando.Users.Menu do
  @moduledoc """
  Menu definitions for the Users Menu. See `Brando.Menu` docs for
  more information
  """
  use Brando.Menu
  import Brando.Gettext

  menu %{
    name: gettext("Users"), anchor: "users", icon: "fa fa-users icon",
    submenu: [
      %{name: gettext("Index"), url: {:admin_user_path, :index}},
      %{name: gettext("Profile"), url: {:admin_user_path, :profile}},
      %{name: gettext("Add new"), url: {:admin_user_path, :new}, role: :superuser}
    ]
  }
end
