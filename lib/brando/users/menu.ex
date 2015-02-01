defmodule Brando.Users.Menu do
  @moduledoc """
  Menu definitions for the Users Menu. See `Brando.Menu` docs for
  more information
  """
  use Brando.Menu

  menu "Brukere", %{name: "Brukere", anchor: "brukere", bgcolor: "#ffaaff", icon: "fa fa-users icon",
                    submenu: [%{name: "Oversikt", url: {:admin_user_path, :index}},
                              %{name: "Profil", url: {:admin_user_path, :profile}},
                              %{name: "Legg til", url: {:admin_user_path, :new}}]}
end