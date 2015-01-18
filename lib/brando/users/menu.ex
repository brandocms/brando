defmodule Brando.Users.Menu do
  @moduledoc """
  Menu definitions for the Users Menu. See `Brando.Menu` docs for
  more information
  """
  use Brando.Menu
  alias Brando, as: B

  menu "Brukere", %{name: "Brukere", anchor: "brukere", bgcolor: "#ffaaff", icon: "fa fa-users icon",
                    submenu: [%{name: "Oversikt", url: B.get_helpers().admin_user_path(B.get_endpoint(), :index)},
                              %{name: "Profil", url: B.get_helpers().admin_user_path(B.get_endpoint(), :profile)},
                              %{name: "Legg til", url: B.get_helpers().admin_user_path(B.get_endpoint(), :new)}]}
end