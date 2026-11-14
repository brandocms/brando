defmodule Mix.Tasks.Brando.Setup do
  use Mix.Task

  @shortdoc "Run the operational setup after brando.install"

  @moduledoc """
  Run the operational setup after `mix brando.install`.

      mix brando.setup
      mix brando.setup --email me@domain.tld --name "Me" --password secret
      mix brando.setup --base-url https://example.com --description "What the site is"
      mix brando.setup --no-assets --no-seeds

  Composes the steps a freshly installed application needs before its first
  request, in order:

    1. `brando.assets.setup` — Yalc publish and consumer asset builds
    2. `ecto.create` and `ecto.migrate`
    3. a superuser account, prompted for unless `--email`/`--name`/`--password`
       are supplied, and skipped when an active superuser already exists. It
       logs in with that password, with no change asked for on first login
    4. `brando.gen.seeds` — identity, SEO, modules, an `index` page, a main
       menu and a footer fragment per configured language. The site's base URL
       and a short description are prompted for (or `--base-url`,
       `--description`) and go into SEO; leave them empty to fill in later.
       With `tenancy_mode: :single` it provisions the site instead
       (`Brando.Setup.Site`): the configured `site_key`, named after
       `:app_name`, in the installation's languages, with Production and
       Staging, created by the first account. Provisioning gives the site that
       content (`Brando.Tenant.Seeder`). A site that exists is left alone.
       With `:multi` nothing is seeded: sites are created at `/admin/sites`,
       and each gets the content then. With either, nothing is asked, and
       `--base-url` and `--description` are unused

  Each step is skipped when its result already exists, so rerunning after a
  failure resumes rather than duplicates. Nothing is removed or rewritten.

  Skip steps with `--no-assets`, `--no-db`, `--no-account` and `--no-seeds`
  (which also skips provisioning the site).
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
    source: :string,
    base_url: :string,
    description: :string
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

    Mix.shell().info([:green, "\n==> Setup complete.\n\n", next_steps(Brando.Tenant.mode())])
  end

  defp next_steps(:single),
    do: "Start the application with `mix phx.server`, open / for the site's homepage and sign in at /admin.\n"

  defp next_steps(:multi),
    do: "Start the application with `mix phx.server`, sign in at /admin and create sites at /admin/sites.\n"

  defp next_steps(_none), do: "Start the application with `mix phx.server` and sign in at /admin.\n"

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
    cond do
      not Keyword.get(opts, :seeds, true) ->
        skip("Seeds")

      Brando.Tenant.mode() == :single ->
        site(opts)

      # Content belongs to a site's environment, and no site exists yet:
      # brando.gen.seeds says so, and that the SEO flags are unused
      Brando.Tenant.enabled?() ->
        step("Seeding default content")
        Mix.Task.run("brando.gen.seeds", seo_args(opts[:base_url], opts[:description]))

      true ->
        seed_content(opts)
    end
  end

  defp site(opts) do
    step("Provisioning the site")
    key = Brando.config(:site_key)

    creator =
      Brando.Setup.Account.superuser() ||
        Mix.raise("No active superuser found. The site needs an account to create it: run mix brando.gen.admin.")

    case Brando.Setup.Site.provision(creator) do
      {:created, site} ->
        Mix.shell().info([
          :green,
          ~s|    + Created the site "#{site.key}", with Production and Staging, and its content in each of its languages\n|
        ])

      {:exists, site} ->
        Mix.shell().info([:yellow, ~s|    = The site "#{site.key}" exists, and is left as it is\n|])

      {:error, reason} ->
        Mix.raise(~s|The site "#{key}" was not created, and nothing of it is left: #{describe(reason)}|)
    end

    for {key, flag} <- [base_url: "--base-url", description: "--description"], opts[key] do
      Mix.shell().info([:yellow, "#{flag} is unused with tenancy: set it in the site's SEO settings."])
    end
  end

  defp describe({:site_setup_failed, reason, _compensation}), do: describe(reason)

  defp describe(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc -> String.replace(acc, "%{#{key}}", to_string(value)) end)
    end)
    |> Enum.map_join(", ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  defp describe(exception) when is_exception(exception), do: Exception.message(exception)
  defp describe(reason), do: inspect(reason)

  defp seed_content(opts) do
    step("Seeding default content")

    base_url =
      Keyword.get_lazy(opts, :base_url, fn -> prompt("Site address (base URL), e.g. https://example.com:", "") end)

    description = Keyword.get_lazy(opts, :description, fn -> prompt("Short description of the site:", "") end)

    Mix.Task.run("brando.gen.seeds", seo_args(base_url, description))
  end

  defp seo_args(base_url, description) do
    [{"--base-url", base_url}, {"--description", description}]
    |> Enum.reject(fn {_flag, value} -> value in [nil, ""] end)
    |> Enum.flat_map(fn {flag, value} -> [flag, value] end)
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
