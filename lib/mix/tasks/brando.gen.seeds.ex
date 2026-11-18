defmodule Mix.Tasks.Brando.Gen.Seeds do
  use Mix.Task

  @shortdoc "Seed default content for a new installation"

  @moduledoc """
  Seed default content for a new installation.

      mix brando.gen.seeds
      mix brando.gen.seeds --user 1
      mix brando.gen.seeds --base-url https://example.com --description "What the site is"
      mix brando.gen.seeds --no-demo

  Creates identity and SEO defaults per configured language, a small set of
  demo content modules, a published `index` page built from them, a main
  navigation menu and a footer fragment. Existing content of each kind is
  left alone, so the task is safe to rerun.

  With `--no-demo` it creates no modules: the `index` page and the footer
  fragment have no blocks, and the rest is the same. To take the demo away
  later, once the site has its own content, run
  `mix brando.seeds.remove_defaults`.

  With `tenancy_mode: :single` or `:multi` it seeds nothing: this content
  belongs to a site's environment, and each site gets it when it is
  provisioned (`Brando.Tenant.Seeder`). In `:single`, `mix brando.setup`
  provisions the site; in `:multi`, sites are created at `/admin/sites`.
  `--base-url`, `--description` and `--no-demo` are unused then, and it says so.

  The seeded content is a starting point for editing in the admin, not a
  migration or an upgrade path.

  `--base-url` and `--description` fill in a new SEO record's base URL and
  fallback meta description; without a base URL, canonical links, sharing
  previews and the sitemap can't give full addresses.

  Requires an account to own the content. Without `--user ID` the oldest
  superuser is used. Create one with `mix brando.gen.admin`.
  """

  @switches [user: :integer, base_url: :string, description: :string, demo: :boolean]

  @impl Mix.Task
  @spec run([binary]) :: :ok
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)

    Application.put_env(:logger, :level, :error)
    Mix.Task.run("app.start")

    if Brando.Tenant.enabled?() do
      banner()

      Mix.shell().info([:yellow, "Nothing seeded: ", tenancy_notice(Brando.Tenant.mode())])

      for {key, flag} <- [base_url: "--base-url", description: "--description"], opts[key] do
        Mix.shell().info([:yellow, "#{flag} is unused with tenancy: set it in the site's SEO settings once it exists."])
      end

      if opts[:demo] == false, do: Mix.shell().info([:yellow, no_demo_notice(Brando.Tenant.mode())])
    else
      seed(opts)
    end
  end

  defp tenancy_notice(:single) do
    """
    with tenancy_mode :single, mix brando.setup creates the site
    #{inspect(Brando.config(:site_key))}, unless it exists, and gives it this content: the identity and SEO,
    the modules, a homepage, the footer fragment and a main menu, in each of its languages.
    """
  end

  defp tenancy_notice(:multi) do
    """
    with tenancy_mode :multi, sites are created at /admin/sites, and each
    gets its content when it is created: the identity and SEO, the modules, a homepage,
    the footer fragment and a main menu, in each of its languages.
    """
  end

  defp no_demo_notice(:single),
    do: "--no-demo is unused here: mix brando.setup --no-demo creates the site without the demo."

  defp no_demo_notice(:multi) do
    "--no-demo is unused here: a site created at /admin/sites gets the demo. " <>
      "Remove it with mix brando.seeds.remove_defaults --site KEY --yes."
  end

  defp seed(opts) do
    user = user!(opts[:user])
    banner()

    {:ok, report} =
      Brando.Setup.Seeds.run(user,
        seo: Keyword.take(opts, [:base_url, :description]),
        demo: Keyword.get(opts, :demo, true)
      )

    for label <- Enum.reverse(report.created), do: Mix.shell().info([:green, "    + #{label}"])
    for label <- Enum.reverse(report.skipped), do: Mix.shell().info([:yellow, "    = #{label} (exists)"])

    Mix.shell().info([:green, "\n==> Done.\n"])

    if Keyword.get(opts, :demo, true) and Enum.any?(Map.values(report.modules)) do
      Mix.shell().info(
        "The homepage and footer are a demo built from the brando-default-* modules. Once the site has " <>
          "its own content, mix brando.seeds.remove_defaults lists what still uses them and removes the rest."
      )
    end
  end

  defp banner do
    Mix.shell().info("""

    ---------------------------
    % Brando Seed Content
    ---------------------------
    """)
  end

  defp user!(nil) do
    case Brando.Setup.Account.superuser() do
      nil ->
        Mix.raise("""
        No active superuser found. Seeded content needs an account to own it.

            mix brando.gen.admin
        """)

      user ->
        user
    end
  end

  defp user!(id) do
    case Brando.Repo.get(Brando.Users.User, id) do
      nil -> Mix.raise("--user #{id} does not identify an account.")
      %{active: false} -> Mix.raise("--user #{id} is not active.")
      %{deleted_at: deleted_at} when not is_nil(deleted_at) -> Mix.raise("--user #{id} is deleted.")
      user -> user
    end
  end
end
