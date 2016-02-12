defmodule Brando.Pages.Menu do
  @moduledoc """
  Menu definitions for the Pages Menu. See `Brando.Menu` docs for
  more information
  """
  use Brando.Menu
  import Brando.Gettext

  menu %{
    name: gettext("Pages"), anchor: "pages", icon: "fa fa-paper-plane icon",
      submenu: [
        %{name: gettext("Index"), url: {:admin_page_path, :index}},
        %{name: gettext("Add new"), url: {:admin_page_path, :new}},
        %{name: gettext("Fragments"), url: {:admin_page_fragment_path, :index}}]}
end
