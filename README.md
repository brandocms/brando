![Brando logo](https://raw.githubusercontent.com/twined/brando/master/priv/static/brando/img/brando-big.png)

[![Build Status](https://travis-ci.org/twined/brando.png?branch=master)](https://travis-ci.org/twined/brando)
[![Coverage Status](https://coveralls.io/repos/twined/brando/badge.png?branch=master)](https://coveralls.io/r/twined/brando?branch=master)
[![Inline docs](http://inch-ci.org/github/twined/brando.png?branch=master)](http://inch-ci.org/github/twined/brando)

*EXPERIMENTAL, DO NOT USE*

Install:
--------
Add Brando and bcrypt to your `deps` and `applications`
in your project's `mix.exs`:

```elixir
def application do
  [mod: {MyApp, []},
   applications: [:phoenix, :cowboy, :logger, :postgrex,
                  :ecto, :bcrypt, :brando]]
end

defp deps do
  [{:bcrypt, github: "opscode/erlang-bcrypt"},
   {:brando, github: "twined/brando"]}
end
```

Add to your `config/config.exs` right before the env-specific import:

```elixir
# insert -- begin
import_config "brando.exs"
# insert -- end
import_config "#{Mix.env}.exs"
```

Add to your relevant `config/%{env}.exs` Repo config:

```elixir
config :my_app, Repo,
  # ...
  extensions: [{Brando.Postgrex.Extension.JSON, library: Poison}]
```

Install Brando:

    $ mix brando.install

Create the database:

    $ mix ecto.create

Run migrations:

    $ mix ecto.migrate

Now for the routes/pipelines/plugs in `web/router.ex`. Switch out
MyApp with your application name:

```elixir
defmodule MyApp.Router do
  use MyApp.Web, :router

  import Brando.Routes.Admin.Users
  import Brando.Routes.Admin.News
  import Brando.Routes.Admin.Images

  alias Brando.Plug.Authenticate

  pipeline :admin do
    plug :accepts, ~w(html json)
    plug :fetch_session
    plug :fetch_flash
    plug :put_layout, {Brando.Admin.LayoutView, "admin.html"}
    plug Authenticate, login_url: "/login"
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/admin", as: :admin do
    pipe_through :admin
    user_resources "/brukere"
    post_resources "/nyheter"
    image_resources "/bilder"
    get "/", Brando.Admin.DashboardController, :dashboard
  end

  scope "/" do
    pipe_through :browser
    get "/login", Brando.AuthController, :login, private: %{model: Brando.User}
    post "/login", Brando.AuthController, :login, private: %{model: Brando.User}
    get "/logout", Brando.AuthController, :logout, private: %{model: Brando.User}
  end
end

```

Static config in `endpoint.ex`:

```elixir
plug Plug.Static,
  at: "/static", from: :brando

plug Plug.Static,
  at: "/media", from: "priv/media"
```

Default login/pass is "admin@twined.net/admin"

Repo config:

```elixir
# configures the repo
config :my_app, MyApp.Repo,
  database: "my_app",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"
  adapter: Ecto.Adapters.Postgres,
  extensions: [{Brando.Postgrex.Extension.JSON, library: Poison}]
```

Optimizing images: (not implemented yet)

```elixir
config :brando, :images, :optimize
  png: [enabled: true,
        bin: "/usr/local/bin/pngquant",
        params: "--speed 1 --force --output \"#{new_filename}\" -- \"#{filename}\""],
  jpeg: [enabled: true,
         bin: "/usr/local/bin/jpegoptim",
         params: "#{filename}"]
```