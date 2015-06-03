![Brando logo](https://raw.githubusercontent.com/twined/brando/master/priv/static/brando/img/brando-big.png)

[![Build Status](https://travis-ci.org/twined/brando.png?branch=master)](https://travis-ci.org/twined/brando)
[![Coverage Status](https://coveralls.io/repos/twined/brando/badge.png?branch=master)](https://coveralls.io/r/twined/brando?branch=master)
[![Inline docs](http://inch-ci.org/github/twined/brando.png?branch=master)](http://inch-ci.org/github/twined/brando)

*EXPERIMENTAL, DO NOT USE*


## Install

Add Brando to your `deps` and `applications` in your project's `mix.exs`:

```elixir
def application do
  [mod: {MyApp, []},
   applications: [:phoenix, :cowboy, :logger, :postgrex,
                  :ecto, :brando]]
end

defp deps do
  [{:brando, github: "twined/brando"]}
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
  import Brando.Routes.Admin.Dashboard
  import Brando.Routes.Admin.Images
  # import Brando.Routes.Admin.Pages
  # import Brando.Routes.Admin.Instagram

  alias Brando.Plug.Authenticate

  pipeline :admin do
    plug :accepts, ~w(html json)
    plug :fetch_session
    plug :fetch_flash
    plug :put_layout, {Brando.Admin.LayoutView, "admin.html"}
    plug Authenticate
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
    dashboard_routes   "/"
    user_routes        "/brukere"
    post_routes        "/nyheter"
    image_routes       "/bilder"
    # instagram_routes "/instagram" 
    # page_routes      "/sider"
  end

  socket "/admin/ws", Brando do
    channel "system:*", SystemChannel
    channel "stats", StatsChannel
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

To use Brando's error view, add to your Endpoint's config:

```elixir
config :my_app, MyApp.Endpoint,
  render_errors: [view: Brando.ErrorView, format: "html"]
```


## Default admin credentials

Default login/pass is `admin@twined.net/admin`


## Sequence

Implements model sequencing.

Controller:

```elixir
  use Brando.Sequence,
    [:controller, [model: Brando.Image,
                   filter: &Brando.Image.get_by_series_id/1]]
```

View:

```elixir
  use Brando.Sequence, :view
```

Model:

```elixir
  use Brando.Sequence, :model

  schema "model" do
    # ...
    sequenced
  end
```

Migration:

```elixir
  use Brando.Sequence, :migration

  def up do
    create table(:model) do
      # ...
      sequenced
    end
  end
```

Template (`sequence.html.eex`):

```html
<ul id="sequence" class="clearfix">
<%= for i <- @items do %>
  <li data-id="<%= i.id %>"><%= i.name %></li>
<% end %>
</ul>
<a id="sort-post" href="<%= Helpers.your_path(@conn, :sequence_post, @filter) %>" class="btn btn-default">
  Lagre rekkefølge
</a>
```


## Tags

Implements tagging in your model.

Add to 

Model:

```elixir
  use Brando.Tag, :model

  schema "model" do
    # ...
    tags
  end
```

Migration:

```elixir
  use Brando.Tag, :migration

  def up do
    create table(:model) do
      # ...
      tags
    end
  end
```


## Instagram

Add to your app's supervision tree:

```elixir
worker(Brando.Instagram.Server, [Brando.Instagram.cfg(:server_name)])
```

Add Instagram to your menu modules in `config/brando.exs`:

```elixir
config :brando, Brando.Menu,
  modules: [Admin, Users, News, Pages, Images, Instagram]
```

Add routes to your app's `web/router.ex` under the `admin` scope:

```elixir
import Brando.Routes.Admin.Instagram

scope "/admin", as: :admin do
  pipe_through :admin
  # ...
  instagram_routes "/instagram"
end
```

Config is found in your app's `config/brando.exs`.

  * `server_name`: An atom naming your server - i.e.: `:myapp_instagram`.
  * `client_id`: Your instagram client id. Find this in the developer section.
  * `interval`: How often we poll for new images
  * `auto_approve`: Set `approved` to `true` on grabbed images
  * `fetch`: What to fetch.
    * `{:user, "your_name"}`
    * `{:tags, ["tag1", "tag2"]}`


## Villain

To use villain outside the built-in `pages` and `news` modules add to your app's `web/router.ex`:

```elixir
import Brando.Routes.Admin.Villain

scope "/admin", as: :admin do
  pipe_through :admin
  # ...
  villain_routes "/whatever/has/villain"
end

```

Include js in `whatever/_scripts.<action>.html.eex`:

```html
<script type="text/javascript" src="/static/brando/js/to-markdown.js" charset="utf-8"></script>
<script type="text/javascript" src="/static/brando/js/markdown.min.js" charset="utf-8"></script>
<script type="text/javascript" src="/static/brando/js/libs/backbone/underscore.js" charset="utf-8"></script>
<script type="text/javascript" src="/static/brando/js/libs/backbone/backbone.js" charset="utf-8"></script>
<script type="text/javascript" src="/static/villain/villain.js" charset="utf-8"></script>
```

Include css in `whatever/_stylesheets.<action>.html.eex`:

```html
<link rel="stylesheet" href="/static/villain/villain.css">
```


## Optimizing images (not implemented yet)

```elixir
config :brando, :images, :optimize
  png: [enabled: true,
        bin: "/usr/local/bin/pngquant",
        params: "--speed 1 --force --output \"#{new_filename}\" -- \"#{filename}\""],
  jpeg: [enabled: true,
         bin: "/usr/local/bin/jpegoptim",
         params: "#{filename}"]
```