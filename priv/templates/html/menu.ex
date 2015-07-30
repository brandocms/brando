defmodule Brando.Menu.<%= String.capitalize(plural) %> do
  @moduledoc """
  Menu definitions for the <%= String.capitalize(plural) %> Menu.

  See `Brando.Menu` docs for more information.
  Install menu by adding to your `config/brando.exs`

      config :brando, Brando.Menu,
        modules: [<%= String.capitalize(plural) %>, ...]

  """
  use Brando.Menu

  menu "no", "<%= String.capitalize(no_plural) %>",
    %{anchor: "<%= plural %>", icon: "fa fa-anchor icon",
      submenu: [%{name: "Oversikt", url: {:<%= admin_path %>_path, :index}},
                %{name: "Legg til", url: {:<%= admin_path %>_path, :new}, role: :admin}]}

  menu "en", "<%= String.capitalize(plural) %>",
    %{anchor: "<%= plural %>", icon: "fa fa-anchor icon",
      submenu: [%{name: "Index", url: {:<%= admin_path %>_path, :index}},
                %{name: "Add", url: {:<%= admin_path %>_path, :new}, role: :admin}]}
end