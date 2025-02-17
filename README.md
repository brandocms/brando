<p align="center">
    <sup><em>A helping hand.</em></sup>
</p>

<p align="center">
<img src="https://raw.githubusercontent.com/brandocms/brando/master/priv/static/brando.png" width="350">
</p>

<p align="center">
    <a href="https://github.com/brandocms/brando/actions/workflows/ci.yml">
      <img src="https://github.com/brandocms/brando/actions/workflows/ci.yml/badge.svg">
    </a>
    <a href="https://coveralls.io/github/brandocms/brando?branch=master">
      <img src="https://coveralls.io/repos/github/brandocms/brando/badge.svg?branch=master">
    </a>
</p>

<p align="center">
*EXPERIMENTAL, NOT RECOMMENDED TO USE BEFORE IN MORE STABLE FORM!*
</p>


## Install

Start by creating a new Phoenix project:

    $ mix phx.new my_project

Run the install script:

    $ wget https://raw.githubusercontent.com/brandocms/brando/master/install.sh && chmod +x install.sh && ./install.sh

Go through `config/brando.exs`.

To use Brando's error views, add to your Endpoint's config (in prod.exs):

```elixir
config :my_app, MyApp.Endpoint,
  render_errors: [
    formats: [html: Brando.ErrorHTML, json: Brando.ErrorJSON], layout: false
  ],
```

*Remember to switch out your ports and configure SSL in `etc/nginx/prod.conf`*

## Dependencies

  * `sharp`/`sharp-cli` for image processing.
    Installation instructions: https://github.com/brandocms/brando/issues/183
  * `gifsicle` for GIF resizing.

## I18n

Brando uses Gettext for i18n.

To extract and merge your frontend and backend translations:
(Example for norwegian)

    $ mix gettext.extract --merge priv/gettext/frontend --locale no --plural-forms-header nplurals="2; plural=(n != 1);"
    $ mix gettext.extract --merge priv/gettext/backend --locale no --plural-forms-header nplurals="2; plural=(n != 1);"


## Generators

Generate blueprint

    $ mix brando.gen.blueprint

Generate templates:

    $ mix brando.gen


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

Add to Dockerfile build:

```bash
$ mix brando.static.deploy
```
