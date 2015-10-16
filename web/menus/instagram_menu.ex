defmodule Brando.Menu.Instagram do
  @moduledoc """
  Menu definitions for the Instagram Menu. See `Brando.Menu` docs for
  more information
  """
  use Brando.Menu
  import Brando.Gettext

  menu "Instagram",
    %{anchor: "instagram", icon: "fa fa-instagram icon",
      submenu: [%{name: gettext("Index"), url: {:admin_instagram_path, :index}}]}
end
