A helping hand.

![Brando logo](https://raw.githubusercontent.com/brandocms/brando/master/priv/templates/brando.install/assets/frontend/static/images/brando/brando-big.png)

![Build Status](https://github.com/brandocms/brando/workflows/CI/badge.svg)
[![Coverage Status](https://coveralls.io/repos/github/brandocms/brando/badge.svg?branch=master)](https://coveralls.io/github/brandocms/brando?branch=master)
[![Inline docs](http://inch-ci.org/github/brandocms/brando.svg?branch=master)](http://inch-ci.org/github/brandocms/brando)

*EXPERIMENTAL, DO NOT USE*


## Install

Start by creating a new Phoenix project:

    $ mix phx.new my_project

Run the install script:

    $ wget https://raw.githubusercontent.com/brandocms/brando/develop/install.sh && chmod +x install.sh && ./install.sh

Go through `config/brando.exs`.

To use Brando's error view, add to your Endpoint's config (in prod.exs):

```elixir
config :my_app, MyApp.Endpoint,
  render_errors: [accepts: ~w(html json), view: Brando.ErrorView, default_format: "html"],
```

*Remember to switch out your ports and configure SSL in `etc/supervisor/prod.conf` and `etc/nginx/prod.conf`*

## Dependencies

  * `imagemagick`/`mogrify` or `sharp`/`sharp-cli` for image processing.
  * `gifsicle` for GIF resizing.


## Datasources

The content editor can access datasources from the frontend.

First register the datasource in your schema:

```elixir
  use Brando.Datasource

  datasource :many, %{
    shareholders: &MyApplication.Shares.list_shareholders/0
  }
```

It's important that the `create`, `update` and `delete` functions in your context file calls
`Brando.Datasource.update_datasource(<schema>, entry)`

Examples here:

```elixir
  @doc """
  Create new artist
  """
  @spec create_artist(params, user | :system) :: {:ok, Artist.t()} | {:error, Ecto.Changeset.t()}
  def create_artist(artist_params, user \\ :system) do
    with changeset <- Artist.changeset(%Artist{}, artist_params, user),
         {:ok, entry} <- Repo.insert(changeset) do
      Brando.Datasource.update_datasource(Artist, entry)
    else
      err -> err
    end
  end

  @doc """
  Update existing artist
  """
  @spec update_artist(id, params, user | :system) ::
          {:ok, Artist.t()} | {:error, Ecto.Changeset.t()}
  def update_artist(artist_id, artist_params, user \\ :system) do
    with {:ok, artist} <- get_artist(artist_id),
         changeset <- Artist.changeset(artist, artist_params, user),
         {:ok, entry} <- Repo.update(changeset) do
      Brando.Datasource.update_datasource(Artist, entry)
    else
      err -> err
    end
  end

  @doc """
  Delete artist by id
  """
  @spec delete_artist(id) :: {:ok, Artist.t()}
  def delete_artist(id) do
    {:ok, entry} = get_artist(id)
    Repo.delete(entry)
    Brando.Datasource.update_datasource(Artist, entry)
  end
```


## I18n

Brando uses Gettext for i18n.

To extract your frontend translations:

    $ mix gettext.extract

Create your frontend translation directories: (for norwegian)

    $ mkdir -p priv/gettext/frontend/nb/LC_MESSAGES

Merge frontend translations

    $ mix gettext.merge priv/gettext/frontend


Now we register our otp app's modules in Brando's registry to automatically set Gettext locales.
Open up you application's `lib/application.ex` and add to `start/2`:

    Brando.Registry.register(MyApp.Web, [:gettext])


## Generator

Generate templates:

    $ mix brando.gen

`name:string avatar:image data:villain image_series:gallery`

Also supports `user:references:users_users` to add a `belongs_to` assoc.

If you use Gettext, register your module in `lib/application.ex`:

```diff
    def start(_type, _args) do
      import Supervisor.Spec, warn: false

      children = [
        # Start the endpoint when the application starts
        supervisor(MyApp.Web.Endpoint, []),
        # Start the Ecto repository
        supervisor(MyApp.Repo, []),
        # Here you could define other workers and supervisors as children
        # worker(MyApp.Worker, [arg1, arg2, arg3]),
      ]

+     Brando.Registry.register(MyAppWeb.MyModule, [:gettext])
```

## Serve static from DO Spaces

Setup Endpoint for `prod.exs`

```elixir
config :my_app, hmr: false
config :my_app, MyAppWeb.Endpoint,
  static_url: [
    scheme: "https",
    host: "cdn.univers.agency",
    path: "/my_app/static",
    port: 443
  ]

config :ex_aws, :s3, %{
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  scheme: "https://",
  host: %{"fra1" => "SPACES_NAME.fra1.digitaloceanspaces.com"},
  region: "fra1"
}
```

Use `Brando.HTML.include_js/0` and `Brando.HTML.include_css/0` right before `</head>`
in `app.html.eex`, since these functions automatically chooses whether to use `path`
or `url` for static asset links.

Add to your frontend `package.json`
```
"build": "webpack --mode=production --config webpack.prod.js",
"build:cdn": "BRANDO_CDN=<%= application_name %> NODE_ENV=production webpack --mode=production --config ./webpack.config.prod.js",
```

Make sure you build frontend with:

```dockerfile
RUN yarn run build.cdn
```

Add to Dockerfile build:

```bash
$ mix brando.static.deploy
```


## Villain templates

Naming guidelines

```
<!-- header block next to text block -->
<div class="v-block" data-v="header|text">

<!-- image with full bleed -->
<div class="v-block" data-v="image+bleed">

<!-- body text with an image underneath -->
<div class="v-block" data-v="body/image">
```

You may reference other fragments by entering

```
${FRAGMENT:index/01_intro/en}
            ^     ^       ^
            |     |       `-- language
            |     `-- fragment key
            `-- parent key
```

## Releases

Brando uses distillery through Docker for release management.

Use the fabric script in `fabfile.py` for deploying and controlling.

    # fab prod -l


## Sequence

Implements schema sequencing.

Schema:

```diff
+ use Brando.Sequence.Schema

  schema "schema" do
    # ...
+   sequenced
  end
```

Migration:

```diff
+ use Brando.Sequence.Migration

  def up do
    create table(:schema) do
      # ...
+     sequenced
    end
  end
```

Admin channel:

```diff
+ use Brando.Sequence.Channel

+ sequence "employees", MyApp.Employee
```

## Lockdown

If you want to limit the availability of your site while developing, you can use the
`Brando.Plug.Lockdown` plug.

If you are authenticated, the website loads normally.

### Example

```elixir
    plug Brando.Plug.Lockdown, [
      layout: {MyApp.LockdownLayoutView, "lockdown.html"},
      view: {MyApp.LockdownView, "lockdown.html"}
    ]
```

### Configure

```elixir
    config :brando,
      lockdown: true,
      lockdown_password: "my_pass",
      lockdown_until: ~N[2016-08-02 19:00:00]
```

Password and time is optional.

If no password configuration is found, you have to login
through the backend to see the frontend website.

You can also add a key as query string to set a cookie that allows browsing.

`http://website/?key=<pass>`


## Tags

Implements tagging in your schema.

Add to

Schema:

```diff
+ use Brando.Tag, :schema

  schema "schema" do
+   tags
  end
```

Migration:

```elixir
+ use Brando.Tag, :migration

  def up do
    create table(:schema) do
+     tags
    end
  end
```

## Page fragments

## Example:

```elixir
import Brando.Pages, only: [fetch_fragment: 2]

fetch_fragment("my/fragment", Gettext.get_locale(MyApp.Gettext)
fetch_fragment("my/fragment", "en")
```

If no language is passed, default language set in `brando.exs` will be used.
If the fragment isn't found, it will render an error box.

## Imagefield

A built in method for adding images to your schema is supplied for you.

In your schema:

```diff

+ use Brando.Field.Image.Schema

  schema "user" do
    field :username, :string
+   field :avatar, Brando.Type.Image
  end

+ has_image_field :avatar, %{
+   allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
+   default_size: :medium,
+   upload_path: Path.join("images", "avatars"),
+   random_filename: true,
+   size_limit: 10_240_000,
+   sizes: %{
+     "micro"  => %{"crop" => false, "quality" => 10, "size" => "25"},
+     "thumb"  => %{"size" => "150x150>", "quality" => 100, "crop" => true},
+     "small"  => %{"size" => "300", "quality" => 100},
+     "medium" => %{"size" => "500", "quality" => 100},
+     "large"  => %{"size" => "700", "quality" => 100},
+     "xlarge" => %{"size" => "900", "quality" => 100}
+   }
+ }
```

The migration's field should be `:text`, not `:string`.


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
