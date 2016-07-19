A helping hand.

![Brando logo](https://raw.githubusercontent.com/twined/brando/develop/priv/templates/brando.install/static/brando/images/brando-big.png)

[![Build Status](https://travis-ci.org/twined/brando.svg?branch=master)](https://travis-ci.org/twined/brando)
[![Coverage Status](https://coveralls.io/repos/github/twined/brando/badge.svg?branch=master)](https://coveralls.io/github/twined/brando?branch=master)
[![Inline docs](http://inch-ci.org/github/twined/brando.svg?branch=master)](http://inch-ci.org/github/twined/brando)

*EXPERIMENTAL, DO NOT USE*


## Install

Start by creating a new phoenix project:

    $ mix phoenix.new my_project

Add Brando to `deps` in your `mix.exs` file:

```elixir
defp deps do
  [{:brando, github: "twined/brando"}]
end
```

Fetch and compile dependencies. Install Brando:

    $ mix do deps.get, deps.compile, brando.install

And then refetch new dependencies Brando has added to your `mix.exs`:

    $ mix do deps.get, deps.compile

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
+  at: "/media", from: Brando.config(:media_path),
+  cache_control_for_etags: "public, max-age=31536000",
+  cache_control_for_vsn_requests: "public, max-age=31536000"
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

Now we register our otp app's modules in Brando's registry to automatically set Gettext locales.
Open up you application's `lib/my_app.ex` and add to `start/2`:

    Brando.Registry.register(MyApp, [:gettext])
    Brando.Registry.register(MyApp.Backend, [:gettext])

## Extra modules

  * [brando_pages](http://github.com/twined/brando_pages)
  * [brando_news](http://github.com/twined/brando_news)
  * [brando_portfolio](http://github.com/twined/brando_portfolio)
  * [brando_instagram](http://github.com/twined/brando_instagram)
  * [brando_analytics](http://github.com/twined/brando_analytics)

## App specific modules

Generate templates:

    $ mix brando.gen.html Task tasks name:string avatar:image data:villain

Also supports `user:references` to add a `belongs_to` assoc.

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

## Popup forms

First, register the form in your app's endpoint startup. The first argument is the
name of the schema, second is the form module and third is a list of fields you want
returned if repo insertion is successful:

```elixir
Brando.PopupForm.Registry.register("client", MyApp.ClientForm, gettext("Create client"), [:id, :name])
```

```javascript
$('.avatar img').click((e) => {
    let clientForm = new PopupForm("client", clientInsertionSuccess);
});

function clientInsertionSuccess(fields) {
    // here you'd insert the returned fields into a select or something similar.
    console.log(`${fields.id} --> ${fields.username}`);
}
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

+ has_image_field :avatar, %{
+   allowed_mimetypes: ["image/jpeg", "image/png"],
+   default_size: :medium,
+   upload_path: Path.join("images", "avatars"),
+   random_filename: true,
+   size_limit: 10240000,
+   sizes: %{
+     "micro"  => %{"size" => "25x25>", "quality" => 100, "crop" => true},
+     "thumb"  => %{"size" => "150x150>", "quality" => 100, "crop" => true},
+     "small"  => %{"size" => "300", "quality" => 100},
+     "medium" => %{"size" => "500", "quality" => 100},
+     "large"  => %{"size" => "700", "quality" => 100},
+     "xlarge" => %{"size" => "900", "quality" => 100}
+   }
+ }
```

The migration's field should be `:text`, not `:string`.

In your controller:

```elixir
import Brando.Plug.Uploads
plug :check_for_uploads, {"user", Brando.User}
     when action in [:create, :profile_update, :update]
```

## Villain

To use villain outside `Brando.Pages` and `Brando.News`, add to your app's `web/router.ex`:

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

Remember to add the `image_series` that Brando looks for.

See `Brando.Villain` help for more information on how to use in your project.

## Brunch

Build for prod with `brunch build --production`.


## Optimizing images

This requires you to have `pngquant`/`cjpeg` installed:

```diff
  config :brando, Brando.Images,
+   optimize: [
+     png: [
+       bin: "/usr/local/bin/pngquant",
+       args: "--speed 1 --force --output %{new_filename} -- %{filename}"
+     ],
+     jpeg: [
+       bin: "/usr/local/bin/cjpeg",
+       args: "-quality 90 %{filename} > %{new_filename}"
+     ]
+   ]
```

or

```diff
  config :brando, Brando.Images,
+   optimize: false
```

## Deployment

Requires fabric.

Configure `./fabfile.py` with your own values.

Make sure your local Docker machine is running, and that the env has been prepared:

    $ docker-machine start default
    $ eval "$(docker-machine env default)"

Ensure that `@version "0.X.0"` is set as module attribute in your `mix.exs` file.

Run

    $ fab prod bootstrap_release

to deploy on your production box.

To build a new release

    $ fab prod deploy_release

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

To upload your local `etc/` folder

    $ fab prod upload_etc
