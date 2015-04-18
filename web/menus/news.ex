defmodule Brando.Menu.News do
  @moduledoc """
  Menu definitions for the News Menu. See `Brando.Menu` docs for
  more information
  """
  use Brando.Menu

  menu "Nyheter", %{name: "Nyheter", anchor: "nyheter", icon: "fa fa-newspaper-o icon",
                    submenu: [
                      %{name: "Oversikt", url: {:admin_post_path, :index}},
                      %{name: "Legg til", url: {:admin_post_path, :new}}]}
end