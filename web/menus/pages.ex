defmodule Brando.Menu.Pages do
  @moduledoc """
  Menu definitions for the Pages Menu. See `Brando.Menu` docs for
  more information
  """
  use Brando.Menu

  menu "Sider", %{name: "Sider", anchor: "sider", icon: "fa fa-paper-plane icon",
                    submenu: [%{name: "Oversikt", url: {:admin_page_path, :index}},
                              %{name: "Legg til", url: {:admin_page_path, :new}},
                              %{name: "Fragmenter", url: {:admin_page_fragment_path, :index}}]}
end