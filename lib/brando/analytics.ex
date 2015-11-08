defmodule Brando.Analytics do
  @moduledoc """
  Analytics is provided through [Eightyfour](http://github.com/twined/eightyfour).
  Follow instructions there, and add the menu to your `config/brando.exs`:

      config :brando, Brando.Menu,
        modules: [..., Brando.Menu.Analytics]

  Finally add to your `router.ex`:

      import Brando.Routes.Admin.Analytics
      # ...
      scope "/admin", as: :admin do
        pipe_through :admin
        # ...
        analytics_routes   "/analytics"
      end

  """
end