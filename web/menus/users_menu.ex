defmodule Brando.Menu.Users do
  @moduledoc """
  Menu definitions for the Users Menu. See `Brando.Menu` docs for
  more information
  """
  use Brando.Menu

  menu "no", "Brukere",
    %{anchor: "users", icon: "fa fa-users icon",
      submenu: [%{name: "Oversikt", url: {:admin_user_path, :index}},
                %{name: "Profil", url: {:admin_user_path, :profile}},
                %{name: "Legg til", url: {:admin_user_path, :new},
                  role: :superuser}]}

  menu "en", "Users",
    %{anchor: "users", icon: "fa fa-users icon",
      submenu: [%{name: "Index", url: {:admin_user_path, :index}},
                %{name: "Profile", url: {:admin_user_path, :profile}},
                %{name: "Add new", url: {:admin_user_path, :new},
                  role: :superuser}]}
end
