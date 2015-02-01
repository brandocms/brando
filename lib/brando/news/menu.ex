defmodule Brando.News.Menu do
  @moduledoc """
  Menu definitions for the News Menu. See `Brando.Menu` docs for
  more information
  """
  use Brando.Menu

  menu "Nyheter", %{name: "Nyheter", anchor: "nyheter", icon: "fa fa-newspaper-o icon",
                    submenu: [
                      %{name: "Legg til", url: {:admin_news_path, :new}}]}
end