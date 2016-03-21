A helping hand.

![Brando logo](https://raw.githubusercontent.com/twined/brando/develop/priv/templates/brando.install/static/brando/images/brando-big.png)

[![Build Status](https://travis-ci.org/twined/brando.svg?branch=master)](https://travis-ci.org/twined/brando)
[![Coverage Status](https://coveralls.io/repos/github/twined/brando/badge.svg?branch=master)](https://coveralls.io/github/twined/brando?branch=master)
[![Inline docs](http://inch-ci.org/github/twined/brando.svg?branch=master)](http://inch-ci.org/github/twined/brando)

*EXPERIMENTAL, DO NOT USE*


## Install

Add Brando to your `deps` and `applications` in your project's `mix.exs`. Also add `brando_villain` to your `deps`:

```elixir
def application do
  [mod: {MyApp, []},
   applications: [:brando, :phoenix, :cowboy, :logger, :postgrex,
                  :ecto, :gettext]]
end

defp deps do
  [{:brando, github: "twined/brando"},
   {:brando_villain, github: "twined/brando_villain"}]
end
```

Fetch and compile dependencies. Install Brando:

    $ mix do deps.get, deps.compile, brando.install

Add to your `config/config.exs` right before the env-specific import:

```diff
+ # Import Brando specific config.
+ import_config "brando.exs"
+
  # Import environment specific config. This must remain at the bottom
  # of this file so it overrides the configuration defined above.
  import_config "#{Mix.env}.exs"
```

Add to your relevant `config/%{env}.exs` Repo config:

```diff
  config :my_app, Repo,
+   extensions: [{Postgrex.Extensions.JSON, library: Poison}]
```

Install NPM packages:

    $ npm install

Install Bower packages:

    $ bower install

Set up database, and seed:

    $ mix ecto.setup

Add to your `config/prod.secret.exs` (see https://github.com/elixir-lang/ecto/issues/1328)

```diff
  config :my_app, MyApp.Repo,
    adapter: Ecto.Adapters.Postgres,
    username: "my_app",
    password: "my_password",
    database: "my_app_prod",
    extensions: [{Postgrex.Extensions.JSON, library: Poison}],
+   socket_options: [recbuf: 8192, sndbuf: 8192],
    pool_size: 20
```


Go through `config/brando.exs`.

Static media config in `endpoint.ex`.

```diff
+ plug Plug.Static,
+  at: "/media", from: Brando.config(:media_path)
```

Also switch out (or add to it, if you use sockets in the frontend as well) the socket config in `endpoint.ex`:

```diff
- socket "/socket", MyApp.UserSocket
+ socket "/admin/ws", Brando.UserSocket
```

To use Brando's error view, add to your Endpoint's config (in prod.exs):

```elixir
config :my_app, MyApp.Endpoint,
  render_errors: [accepts: ~w(html json), view: Brando.ErrorView, default_format: "html"],
```

Brando uses Gettext for i18n.

To extract your frontend translations:

    $ mix gettext.extract

Create your frontend translation directories: (for norwegian)

    $ mkdir -p priv/gettext/frontend/nb/LC_MESSAGES

And backend:

    $ mkdir -p priv/gettext/backend/nb/LC_MESSAGES

Merge frontend translations

    $ mix gettext.merge priv/gettext/frontend

And backend:

    $ mix gettext.merge priv/gettext/backend

## Extra modules

  * [brando_pages](http://github.com/twined/brando_pages)
  * [brando_news](http://github.com/twined/brando_news)
  * [brando_portfolio](http://github.com/twined/brando_portfolio)
  * [brando_instagram](http://github.com/twined/brando_portfolio)

## App specific modules

Generate templates:

    $ mix brando.gen.html Task tasks name:string avatar:image data:villain

Copy outputted routes and add to `web/router.ex`

Register your module in `lib/my_app.ex`:

```diff
    def start(_type, _args) do
      import Supervisor.Spec, warn: false

      children = [
        # Start the endpoint when the application starts
        supervisor(MyApp.Endpoint, []),
        # Start the Ecto repository
        supervisor(MyApp.Repo, []),
        # Here you could define other workers and supervisors as children
        # worker(MyApp.Worker, [arg1, arg2, arg3]),
      ]

+     Brando.Registry.register(MyApp.MyModule, [:menu])
```

## Production

Run the `compile` script in your OTP app's dir to `git pull` latest, get latest hex deps,
compile and build production assets.

### Additional admin CSS/styling

For modules added through your OTP app, you can style its backend by editing
`web/static/css/custom/brando.custom.scss`, or adding your own files to `web/static/css/custom/`. Remember to include these from `brando.custom.scss`.

### Additional admin Javascript

Add files to your `web/static/js/admin` folder. These are compiled down to `priv/static/js/brando.custom.js`. This file is included in the admin section's base template.

## Pagination

For pagination, add to your app's `repo.ex`:

```diff
  defmodule MyApp.Repo do
    use Ecto.Repo, otp_app: :my_app
+   use Scrivener
  end
```

See Scrivener's docs for usage: https://hexdocs.pm/scrivener/

## Default admin credentials

Default login/pass is `admin@twined.net/admin`


## Sequence

Implements model sequencing.

Controller:

```elixir
  use Brando.Sequence,
    [:controller, [model: MyApp.Model,
                   filter: &MyApp.Model.by_collection_id/1]]
```

The filter should return items by the :filter param in your routes.ex.

Example of a filter

```elixir
def by_collection_id(id) do
  __MODULE__
  |> where([c], collection.id == ^id)
  |> order_by([c], c.sequence)
end
```

View:

```elixir
  use Brando.Sequence, :view
```

Model:

```diff
+ use Brando.Sequence, :model

  schema "model" do
    # ...
+   sequenced
  end
```

Migration:

```diff
+ use Brando.Sequence, :migration

  def up do
    create table(:model) do
      # ...
+     sequenced
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

Add a link to the sequencer from your main template:

```html
<a href="<%= Helpers.admin_your_path(@conn, :sequence, filter_id) %>" class="btn btn-default m-b-sm">
  <i class="fa fa-sort"></i> Sort
</a>
```

or add to tablize:

```elixir
{"Sort this category", "fa-sort", :admin_your_path, :sequence, :id}
```

Finally, add to your routes (`web/router.ex`):

```elixir
  get    "/route/:filter/sorter", YourController, :sequence
  post   "/route/:filter/sorter", YourController, :sequence_post
```

## Tags

Implements tagging in your model.

Add to

Model:

```diff
+ use Brando.Tag, :model

  schema "model" do
+   tags
  end
```

Migration:

```elixir
+ use Brando.Tag, :migration

  def up do
    create table(:model) do
+     tags
    end
  end
```


## Instagram

Add to your app's supervision tree:

```diff
  children = [
    # Start the endpoint when the application starts
    supervisor(MyApp.Endpoint, []),
    # Start the Ecto repository
    supervisor(MyApp.Repo, []),
+   worker(Brando.Instagram, [])
  ]
```

Add Instagram to your menu modules in `config/brando.exs`:

```diff
  config :brando, Brando.Menu,
    modules: [Admin, Users, News, Pages, Images,
+             Instagram]
```

Add routes to your app's `web/router.ex` under the `admin` scope:

```diff
+ import Brando.Instagram.Routes.Admin

  scope "/admin", as: :admin do
    pipe_through :admin
+   instagram_routes "/instagram"
  end
```

Config is found in your app's `config/brando.exs`.

  * `client_id`: Your instagram client id. Find this in the developer section.
  * `interval`: How often we poll for new images
  * `auto_approve`: Set `approved` to `true` on grabbed images
  * `sizes`: A map of sizes to create on download.
  * `query`: What to query.
    * `{:user, "your_name"}`
    * `{:tags, ["tag1", "tag2"]}`

## Analytics

Analytics is provided through [Eightyfour](http://github.com/twined/eightyfour).

Add to your app's supervision tree:

```diff
  children = [
    # Start the endpoint when the application starts
    supervisor(MyApp.Endpoint, []),
    # Start the Ecto repository
    supervisor(MyApp.Repo, []),
+   worker(Brando.Eightyfour, [])
  ]
```

Add to your `config/brando.exs`

```elixir
config :brando, Brando.Menu,
  modules: [..., Brando.Menu.Analytics]
```

Finally add to your `router.ex`:

```diff
+ import Brando.Analytics.Routes.Admin

  scope "/admin", as: :admin do
    pipe_through :admin
+   analytics_routes   "/analytics"
  end
```

## Page fragments

## Example:

```elixir
import Brando.Pages.Utils, only: [render_fragment: 2]

render_fragment("my/fragment", Gettext.get_locale(MyApp.Gettext)
render_fragment("my/fragment", "en")
```

If no language is passed, the default language set in `brando.exs` as `default_language` will be used.

If the fragment isn't found, it will render an error box.

## Imagefield

A built in method for adding images to your model is supplied for you.

In your model:

```diff

+ use Brando.Field.ImageField

  schema "user" do
    field :username, :string
+   field :avatar, Brando.Type.Image
  end

+ has_image_field :avatar,
+   %{allowed_mimetypes: ["image/jpeg", "image/png"],
+     default_size: :medium,
+     upload_path: Path.join("images", "avatars"),
+     random_filename: true,
+     size_limit: 10240000,
+     sizes: %{
+       "micro"  => %{"size" => "25x25>", "quality" => 100, "crop" => true},
+       "thumb"  => %{"size" => "150x150>", "quality" => 100, "crop" => true},
+       "small"  => %{"size" => "300", "quality" => 100},
+       "medium" => %{"size" => "500", "quality" => 100},
+       "large"  => %{"size" => "700", "quality" => 100},
+       "xlarge" => %{"size" => "900", "quality" => 100}
+     }
+   }
```

The migration's field should be `:text`, not `:string`.

In your controller:

```elixir
import Brando.Plug.Uploads
plug :check_for_uploads, {"user", Brando.User}
     when action in [:create, :profile_update, :update]
```

## Villain

To use villain outside the built-in `pages` and `news` modules add to your app's `web/router.ex`:

```diff
+ import Brando.Villain.Routes.Admin

  scope "/admin", as: :admin do
    pipe_through :admin
+   villain_routes "/whatever/has/villain", YourController
  end

```

Include js in `whatever/_scripts.<action>.html.eex`:

```html
<%= Brando.Villain.HTML.include_scripts %>
```

Include css in `whatever/_stylesheets.<action>.html.eex`:

```html
<link rel="stylesheet" href="<%= Helpers.static_path(@conn, "/css/villain.css") %>">
```

Initialize Villain in your template:

```html
<%= Brando.Villain.HTML.initialize(
      base_url:     "/admin/news/",
      image_series: "news",
      source:       "textarea[name=\"post[data]\"]") %>
```

If you have custom blocks, add them in your `config/brando.exs`:

```elixir
config :brando, Brando.Villain,
  extra_blocks: ["MyBlock", "AnotherBlock"]
```

See `Brando.Villain` help for more information on how to use in your project.

## Bower/Brunch

Currently these packages are auto-installed:

* jQuery - https://github.com/jquery/jquery
* flexslider - https://github.com/woothemes/FlexSlider
* salvattore - https://github.com/rnmp/salvattore
* jscroll - https://github.com/pklauzinski/jscroll/

Add more packages to your bower.json, and brunch will automatically include them.

Build for prod with `brunch build`.


## Optimizing images

This requires you to have `pngquant` installed.

```diff
  config :brando, Brando.Images,
+   optimize: [
+     png: [bin: "/usr/local/bin/pngquant",
+           args: "--speed 1 --force --output %{new_filename} -- #{filename}"]]
```

or

```diff
  config :brando, Brando.Images,
+   optimize: false
```

## Deployment

Requires fabric.

Configure `./fabfile.py` with your own values.

Run

    $ fab prod bootstrap_release:0.1.0

to deploy on your production box.

To seed your DB:

    $ fab prod seed

To dump local db to .sql

    $ fab dump_localdb

To upload local db to remote

    $ fab prod upload_db

To load remote db

    $ fab prod load_db

To dump/upload/load local db to remote:

    $ fab prod dump_and_load_db

To upload your local `media/` folder (only runs if remote `media/` doesn't exists!)

    $ fab prod upload_media
