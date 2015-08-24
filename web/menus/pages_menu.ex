defmodule Brando.Menu.Pages do
  @moduledoc """
  Menu definitions for the Pages Menu. See `Brando.Menu` docs for
  more information
  """
  use Brando.Menu

  menu "no", "Sider",
    %{anchor: "pages", icon: "fa fa-paper-plane icon",
      submenu: [
        %{name: "Oversikt", url: {:admin_page_path, :index}},
        %{name: "Legg til", url: {:admin_page_path, :new}},
        %{name: "Fragmenter", url: {:admin_page_fragment_path, :index}}]}

  menu "en", "Pages",
    %{anchor: "pages", icon: "fa fa-paper-plane icon",
      submenu: [
        %{name: "Index", url: {:admin_page_path, :index}},
        %{name: "Add new", url: {:admin_page_path, :new}},
        %{name: "Fragments", url: {:admin_page_fragment_path, :index}}]}
end
