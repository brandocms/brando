defmodule Brando.Menu.Images do
  @moduledoc """
  Menu definitions for the Images Menu. See `Brando.Menu` docs for
  more information
  """
  use Brando.Menu

  menu "no", "Bilder",
    %{anchor: "images", icon: "fa fa-picture-o icon",
      submenu: [%{name: "Oversikt", url: {:admin_image_path, :index}}]}

  menu "en", "Images",
    %{anchor: "images", icon: "fa fa-picture-o icon",
      submenu: [%{name: "Index", url: {:admin_image_path, :index}}]}
end
