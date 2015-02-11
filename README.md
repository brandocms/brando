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
   {:ecto, "~> 0.7"},
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

    $ mix ecto.create

Create an initial migration for the `users` table:

    $ mix ecto.gen.migration add_users_table

then add the following to the generated file

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
      add :role,          :integer
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

    $ mix ecto.migrate

Routes/pipelines/plugs in `router.ex`:

```elixir
import Brando.Users.Admin.Routes
alias Brando.Plugs.Authenticate

pipeline :admin do
  plug :accepts, ~w(html json)
  plug :fetch_session
  plug :fetch_flash
  plug :put_layout, {Brando.Admin.LayoutView, "admin.html"}
  plug Authenticate, login_url: "/login"
end

scope "/admin", as: :admin do
  pipe_through :admin
  users_resources "/brukere", private: %{model: Brando.Users.Model.User}
  get "/", Brando.Dashboard.Admin.DashboardController, :dashboard

end

scope "/" do
  pipe_through :browser
  get "/login", Brando.Auth.AuthController, :login,
    private: %{model: Brando.Users.Model.User,
               layout: {Brando.Auth.LayoutView, "auth.html"}}
  post "/login", Brando.Auth.AuthController, :login,
    private: %{model: Brando.Users.Model.User,
               layout: {Brando.Auth.LayoutView, "auth.html"}}
  get "/logout", Brando.Auth.AuthController, :logout,
    private: %{model: Brando.Users.Model.User,
               layout: {Brando.Auth.LayoutView, "auth.html"}}
end
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
  static_url: "/static",
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

News
====

Create an initial migration for the `posts` table:

    $ mix ecto.gen.migration add_posts_table

then add the following to the generated file:

```elixir
defmodule MyApp.Repo.Migrations.AddPostsTable do
  use Ecto.Migration

  def up do
    create table(:posts) do
      add :language,          :text
      add :header,            :text
      add :slug,              :text
      add :lead,              :text
      add :data,              :json
      add :cover,             :text
      add :status,            :integer
      add :creator_id,        references(:user)
      add :meta_description,  :text
      add :meta_keywords,     :text
      add :featured,          :boolean
      add :published,         :boolean
      add :publish_at,        :datetime
      timestamps
    end
    create index(:posts, [:language])
    create index(:posts, [:slug])
    create index(:posts, [:status])
  end

  def down do
    drop table(:posts)
    drop index(:posts, [:language])
    drop index(:posts, [:slug])
    drop index(:posts, [:status])
  end
end
```

Now run the migration:

    $ mix ecto.migrate



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