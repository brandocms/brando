defmodule Brando.Menu.<%= String.capitalize(plural) %> do
  @moduledoc """
  Menu definitions for the <%= String.capitalize(plural) %> Menu.

  See `Brando.Menu` docs for more information.
  Install menu by adding to your `config/brando.exs`

      config :brando, Brando.Menu,
        modules: [<%= String.capitalize(plural) %>, ...]

  """
  use Brando.Menu

  menu "<%= String.capitalize(plural) %>",
    %{name: "<%= String.capitalize(plural) %>", anchor: "<%= plural %>", icon: "fa fa-anchor icon",
      submenu: [%{name: "Oversikt", url: {:<%= admin_path %>_path, :index}},
                %{name: "Legg til", url: {:<%= admin_path %>_path, :new}, role: :admin}]}
end