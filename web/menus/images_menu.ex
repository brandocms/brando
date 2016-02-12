defmodule Brando.Images.Menu do
  @moduledoc """
  Menu definitions for the Images Menu. See `Brando.Menu` docs for
  more information
  """
  use Brando.Menu
  import Brando.Gettext

  menu %{
    name: gettext("Images"), anchor: "images", icon: "fa fa-picture-o icon",
      submenu: [%{name: gettext("Index"), url: {:admin_image_path, :index}}]}
end
