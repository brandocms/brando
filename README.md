![Brando logo](https://raw.githubusercontent.com/twined/brando/develop/priv/install/templates/static/brando/images/brando-big.png)

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
  [{:brando, github: "twined/brando"}]
end
```

Install your deps:

    $ mix do deps.get, deps.compile

Install Brando:

    $ mix brando.install

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
  extensions: [{Postgrex.Extensions.JSON library: Poison}]
```

Install bower frontend dependencies:

    $ bower install

Create the database:

    $ mix ecto.create

Run migrations:

    $ mix ecto.migrate

Run seeds to add default image categories/series and admin user:

    $ mix run priv/repo/seeds.exs

Go through `config/brando.exs`.

Make sure you set `:brando, :media_path` to your `media` folder. This must be an absolute path! 

Static config in `endpoint.ex`. (Make sure you add `images` to the `only` key):

```elixir
plug Plug.Static,
  at: "/", from: :my_app, gzip: false,
  only: ~w(css images js fonts favicon.ico robots.txt)

plug Plug.Static,
  at: "/media", from: Brando.config(:media_path)
```

To use Brando's error view, add to your Endpoint's config:

```elixir
config :my_app, MyApp.Endpoint,
  render_errors: [view: Brando.ErrorView, default_format: "html"]
```

## Pagination

For pagination, add to your app's `repo.ex`:

```elixir

defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app
  use Scrivener
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
                   filter: &MyApp.Model.get_by_collection_id/1]]
```

The filter should return items by the :filter param in your routes.ex.

Example of a filter

```elixir
def get_by_collection_id(id) do
  __MODULE__
  |> where([c], collection.id == ^id)
  |> order_by([c], c.sequence)
  |> Brando.repo.all
end
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
supervisor(Brando.Instagram, [MyApp.Instagram])
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

  * `server_name`: A name for your server, e.g. `MyApp.Instagram.Server`
  * `client_id`: Your instagram client id. Find this in the developer section.
  * `interval`: How often we poll for new images
  * `auto_approve`: Set `approved` to `true` on grabbed images
  * `fetch`: What to fetch.
    * `{:user, "your_name"}`
    * `{:tags, ["tag1", "tag2"]}`


## Imagefield

A built in method for adding images to your model is supplied for you.

In your model:

```elixir

use Brando.Field.ImageField

schema "user" do
  field :username, :string
  field :avatar, Brando.Type.Image
end

has_image_field :avatar,
  %{allowed_mimetypes: ["image/jpeg", "image/png"],
    default_size: :medium,
    upload_path: Path.join("images", "avatars"),
    random_filename: true,
    size_limit: 10240000,
    sizes: %{
      "micro"  => %{"size" => "25x25>", "quality" => 100, "crop" => true},
      "thumb"  => %{"size" => "150x150>", "quality" => 100, "crop" => true},
      "small"  => %{"size" => "300", "quality" => 100},
      "medium" => %{"size" => "500", "quality" => 100},
      "large"  => %{"size" => "700", "quality" => 100},
      "xlarge" => %{"size" => "900", "quality" => 100}
    }
  }
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
<%= Brando.Villain.HTML.include_scripts %>
```

Include css in `whatever/_stylesheets.<action>.html.eex`:

```html
<link rel="stylesheet" href="<% Helpers.static_path(@conn, "/css/villain.css") %>">
```

Initialize Villain in your template:

```html
<%= Brando.Villain.HTML.initialize(
      browse_url: "/admin/news/villain/browse/post",
      upload_url: "/admin/news/villain/upload/post",
      source:     "textarea[name=\"post[data]\"]") %>
```

If you have custom blocks, add them in your `config/brando.exs`:

```elixir
config :brando, Brando.Villain,
  extra_blocks: ["MyBlock", "AnotherBlock"]
```

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

```elixir
config :brando, Brando.Images,
  optimize: [
    png: [bin: "/usr/local/bin/pngquant",
          args: "--speed 1 --force --output %{new_filename} -- #{filename}"]]
```

or

```elixir
config :brando, Brando.Images,
  optimize: false
```

## Deployment

Requires fabric.

Configure `./fabfile.py` with your own values.

Run

    $ fab prod bootstrap

