![Brando logo](https://raw.githubusercontent.com/twined/brando/master/priv/static/brando/img/brando-big.png)

[![Build Status](https://travis-ci.org/twined/brando.png?branch=master)](https://travis-ci.org/twined/brando)
[![Coverage Status](https://coveralls.io/repos/twined/brando/badge.png?branch=master)](https://coveralls.io/r/twined/brando?branch=master)
[![Inline docs](http://inch-ci.org/github/twined/brando.png?branch=master)](http://inch-ci.org/github/twined/brando)

*EXPERIMENTAL, DO NOT USE*

Install:
--------
Add Brando, Ecto, bcrypt and postgrex to your `deps` and `applications`
in your project's `mix.exs`:

```elixir
def application do
  [mod: {MyApp, []},
   applications: [:phoenix, :cowboy, :logger, :postgrex,
                  :ecto, :bcrypt, :brando]]
end

defp deps do
  [{:postgrex, "~> 0.7"},
   {:ecto, "~> 0.6"},
   {:bcrypt, github: "opscode/erlang-bcrypt"},
   {:brando, github: "twined/brando"]}
end
```

Remember to start the Ecto repo in your `lib/my_app.ex`:

```elixir
children = [
  # Define workers and child supervisors to be supervised
  # worker(MyApp.Worker, [arg1, arg2, arg3])
  worker(MyApp.Repo, [])
]
```

Install Brando:

    $ mix brando.install

Create the database:

    $ mix ecto.create MyApp.Repo

Create an initial migration for the `users` table:

    $ mix ecto.gen.migration MyApp.Repo add_users_table

then add the following to the generated file: (old syntax)

```elixir
defmodule MyApp.Repo.Migrations.AddUsersTable do
  use Ecto.Migration

  def up do
    ["CREATE TABLE users (
        id serial PRIMARY KEY,
        username text,
        full_name text,
        email text UNIQUE,
        password text,
        avatar text,
        role integer,
        last_login timestamp,
        inserted_at timestamp,
        updated_at timestamp)",

      "CREATE UNIQUE INDEX ON users (lower(username))"]
  end

  def down do
    "DROP TABLE IF EXISTS users"
  end
end
```

or new syntax (~> 0.6.0):

```elixir
defmodule MyApp.Repo.Migrations.AddUsersTable do
  use Ecto.Migration

  def up do
    create table(:users) do
      add :username,      :text
      add :full_name,     :text
      add :email,         :text
      add :password,      :text
      add :avatar,        :text
      add :administrator, :bool
      add :editor,        :bool
      add :last_login,    :datetime
      timestamps
    end
    create index(:users, [:username], unique: true)
    create index(:users, [:email], unique: true)
  end

  def down do
    drop table(:users)
    drop index(:users, [:username], unique: true)
    drop index(:users, [:email], unique: true)
  end
end
```

Now run the migration:

    $ mix ecto.migrate MyApp.Repo

Routes/pipelines/plugs in `router.ex`:

```elixir
alias Brando.Plugs.Authenticate
plug Authenticate, login_url: "/login"
```

Endpoint config in `endpoint.ex`:

```elixir
plug Plug.Static,
  at: "/static", from: :brando

plug Plug.Static,
  at: "/media", from: "priv/media"
```

Configuration:
--------------

In your `config/config.exs`:

```elixir
config :brando,
  app_name: "MyApp",
  router: MyApp.Router,
  endpoint: MyApp.Endpoint,
  repo: MyApp.Repo,
  media_url: "/media",
  templates_path: "path/to/brando/templates",
  use_modules: [MyApp.Admin, MyApp.Users, MyApp.MyModule],
  menu_colors: ["#FBA026;", "#F87117;", "#CF3510;", "#890606;", "#FF1B79;",
                "#520E24;", "#8F2041;", "#DC554F;", "#FF905E;", "#FAC51C;",
                "#D6145F;", "#AA0D43;", "#7A0623;", "#430202;", "#500422;",
                "#870B46;", "#D0201A;", "#FF641A;"]

config :my_app, MyApp.Repo,
  database: "my_app",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"
```

Mugshots
========

Image processing and thumbnails for Brando

Config
------
Optimizing images: (not implemented yet)

```elixir
config :brando, :mugshots, :optimize
  png: [enabled: true,
        bin: "/usr/local/bin/pngquant",
        params: "--speed 1 --force --output \"#{new_filename}\" -- \"#{filename}\""],
  jpeg: [enabled: true,
         bin: "/usr/local/bin/jpegoptim",
         params: "#{filename}"]
```