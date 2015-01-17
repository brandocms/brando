defmodule Brando.Users.Menu do
  use Brando.Menu

  menu "Brukere", %{name: "Brukere", anchor: "brukere", bgcolor: "#ffaaff", icon: "fa fa-users icon",
                    submenu: [%{name: "Oversikt", url: Brando.get_helpers().admin_user_path(Brando.get_endpoint(), :index)},
                              %{name: "Profil", url: Brando.get_helpers().admin_user_path(Brando.get_endpoint(), :profile)},
                              %{name: "Legg til", url: Brando.get_helpers().admin_user_path(Brando.get_endpoint(), :new)}]}
end