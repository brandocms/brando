defmodule Mix.Tasks.Brando.Setup do
  use Mix.Task

  @shortdoc "Run the operational setup after brando.install"

  @moduledoc """
  Run the operational setup after `mix brando.install`.

      mix brando.setup
      mix brando.setup --email me@domain.tld --name "Me" --password secret
      mix brando.setup --no-assets --no-seeds

  Composes the steps a freshly installed application needs before its first
  request, in order:

    1. `brando.assets.setup` — Yalc publish and consumer asset builds
    2. `ecto.create` and `ecto.migrate`
    3. a superuser account, prompted for unless `--email`/`--name`/`--password`
       are supplied, and skipped when an active superuser already exists
    4. `brando.gen.seeds` — identity, SEO, modules, an `index` page, a main
       menu and a footer fragment per configured language

  Each step is skipped when its result already exists, so rerunning after a
  failure resumes rather than duplicates. Nothing is removed or rewritten.

  Skip steps with `--no-assets`, `--no-db`, `--no-account` and `--no-seeds`.
  Pass `--source PATH` to hand a Brando JavaScript source to asset setup.

  This task operates on the database and the filesystem. Source generation
  belongs to `mix brando.install`, which must be accepted first.
  """

  @switches [
    assets: :boolean,
    db: :boolean,
    account: :boolean,
    seeds: :boolean,
    email: :string,
    name: :string,
    password: :string,
    source: :string
  ]

  @impl Mix.Task
  @spec run([binary]) :: :ok
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)

    Mix.shell().info("""

    ---------------------------
    % Brando Setup
    ---------------------------
    """)

    assets(opts)
    database(opts)

    Application.put_env(:logger, :level, :error)
    Mix.Task.run("app.start")

    account(opts)
    seeds(opts)

    Mix.shell().info([
      :green,
      """

      ==> Setup complete.

      Start the application with `mix phx.server` and sign in at /admin.
      """
    ])
  end

  defp assets(opts) do
    if Keyword.get(opts, :assets, true) do
      step("Building assets")
      args = if opts[:source], do: ["--source", opts[:source]], else: []
      Mix.Task.run("brando.assets.setup", args)
    else
      skip("Assets")
    end
  end

  defp database(opts) do
    if Keyword.get(opts, :db, true) do
      step("Creating and migrating the database")
      Mix.Task.run("ecto.create")
      Mix.Task.run("ecto.migrate")
    else
      skip("Database")
    end
  end

  defp account(opts) do
    cond do
      not Keyword.get(opts, :account, true) ->
        skip("Account")

      superuser = Brando.Setup.Account.superuser() ->
        skip("Account (#{superuser.email} exists)")

      true ->
        step("Creating superuser")

        Brando.Setup.Account.create_superuser(%{
          email: opts[:email] || prompt("Email address:", "admin@brandocms.com"),
          name: opts[:name] || prompt("Name:", "Brando CMS"),
          password: opts[:password] || password!()
        })
    end
  end

  defp seeds(opts) do
    if Keyword.get(opts, :seeds, true) do
      step("Seeding default content")
      Mix.Task.run("brando.gen.seeds")
    else
      skip("Seeds")
    end
  end

  defp password! do
    case Mix.Tasks.Brando.Gen.Admin.password_get("Account password:", true) do
      password when is_binary(password) ->
        case String.trim(password) do
          "" -> Mix.raise("A password is required. Supply --password for unattended setup.")
          password -> password
        end

      _ ->
        Mix.raise("No password was supplied. Use --password for unattended setup.")
    end
  end

  defp prompt(prompt, default) do
    case Mix.Brando.prompt("+ #{prompt} [#{default}]") do
      "" -> default
      answer -> answer
    end
  end

  defp step(message), do: Mix.shell().info([:blue, "\n==> #{message}\n"])
  defp skip(message), do: Mix.shell().info([:yellow, "==> #{message} skipped\n"])
end
