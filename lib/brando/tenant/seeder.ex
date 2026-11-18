defmodule Brando.Tenant.Seeder do
  @moduledoc """
  Default starting content for a site's languages.

  Provisioning runs `c:seed/3` in a new site's Production environment, which
  Staging is then copied from. A language added to an existing site later
  (`Brando.Tenant.Registry.update_site/3`) is seeded in each of the site's
  environments by `c:seed_language/4`, in a job per environment
  (`Brando.Worker.SiteLanguageSeed`).

  For each language it creates an identity named after the site and an SEO
  record, and then what `mix brando.setup` seeds for a single-site
  installation (`Brando.Setup.Seeds`): the modules, a published homepage built
  from them, the footer fragment and a main menu. Each is skipped when it
  already exists in that language, so seeding a language again, or one that
  was removed from the site and added back, changes nothing. A language added
  later gets no modules: its homepage is built from the ones the site has,
  and only when it has no page at all (`seed_language/4`).

  It writes as the system, with the creating user as the creator of what has
  one: provisioning has already checked that the user may create sites, and
  the user may hold no rights in the new site's content (`authorization_mode:
  :groups`), which admits no one while it is suspended.

  An application configures its own seeder, a module implementing `c:seed/3`,
  as `config :brando, tenant_seeder: MyApp.TenantSeeder`. It replaces this
  one: call `seed/3` from it to keep this content, or create the identity and
  SEO records yourself. For a language added later it is asked for
  `c:seed_language/4`, an optional callback; one that does not define it gets
  this module's `seed_language/4`.
  """

  alias Brando.Environments.Environment
  alias Brando.Repo
  alias Brando.Sites
  alias Brando.Sites.Site
  alias Brando.Users.User

  @doc "Seeds every one of `site`'s languages in a newly provisioned environment."
  @callback seed(Site.t(), Environment.t(), User.t()) :: :ok | {:error, term()}

  @doc """
  Seeds `language`, just added to `site`, in one of its environments, which
  may already hold content in that language: leave that alone. Runs in the
  environment, in a job that is retried when it returns an error or raises.
  """
  @callback seed_language(Site.t(), Environment.t(), language :: String.t(), User.t()) :: :ok | {:error, term()}

  @doc """
  As `c:seed/3`, with options: `demo: false` asks for the content without the
  demo modules (`mix brando.setup --no-demo`). Optional: provisioning calls
  it only for `demo: false`, and calls `c:seed/3` of a seeder without it.
  """
  @callback seed(Site.t(), Environment.t(), User.t(), keyword()) :: :ok | {:error, term()}

  @optional_callbacks seed_language: 4, seed: 4

  @behaviour __MODULE__

  @impl true
  def seed(%Site{} = site, %Environment{} = environment, %User{} = creator), do: seed(site, environment, creator, [])

  @doc """
  Seeds every one of `site`'s languages, as `seed/3`; with `demo: false`
  without the demo modules: the homepage and the footer fragment have no
  blocks (`Brando.Setup.Seeds`).
  """
  @impl true
  def seed(%Site{} = site, %Environment{}, %User{} = creator, opts) when is_list(opts),
    do: seed_languages(site, site.languages, creator, Keyword.take(opts, [:demo]))

  @doc """
  The default `c:seed_language/4`: the identity, SEO record, footer fragment
  and main menu in `language`, each unless it exists (a trashed one counts),
  and the homepage when the language has no page at all. It never inserts,
  restores or changes a module, which every language shares: the homepage is
  built from the seed's modules that remain (`Brando.Setup.Seeds`).
  """
  @impl true
  def seed_language(%Site{} = site, %Environment{}, language, %User{} = creator) when is_binary(language),
    do: seed_languages(site, [language], creator, added: true)

  @doc """
  Seeds `language` in `environment` with the installation's configured seeder:
  its `c:seed_language/4`, or this module's when it has none. Runs in the
  current environment.
  """
  @spec seed_added_language(Site.t(), Environment.t(), String.t(), User.t()) :: :ok | {:error, term()}
  def seed_added_language(site, environment, language, creator) do
    seeder = configured()
    Code.ensure_loaded(seeder)

    if function_exported?(seeder, :seed_language, 4),
      do: seeder.seed_language(site, environment, language, creator),
      else: seed_language(site, environment, language, creator)
  end

  @doc "The installation's seeder: `config :brando, tenant_seeder:`, or this module."
  @spec configured() :: module()
  def configured, do: Brando.config(:tenant_seeder) || __MODULE__

  defp seed_languages(site, languages, creator, opts) do
    languages = Enum.map(languages, &String.to_existing_atom/1)

    {:ok, :ok} =
      Repo.transaction(fn ->
        Enum.each(languages, &identity_and_seo(site, &1))
        {:ok, _report} = Brando.Setup.Seeds.run(creator, [languages: languages, actor: :system] ++ opts)
        :ok
      end)

    :ok
  rescue
    exception -> {:error, exception}
  end

  # The default identity's name and titles are placeholders. The site's name
  # replaces them, as the application's does in an installation without
  # tenancy; in `:multi` the identity's name is what the site's pages go by
  # (`Brando.Sites.site_name/1`).
  defp identity_and_seo(site, language) do
    unless Repo.get_by(Sites.Identity, language: language) do
      language
      |> Sites.create_default_identity()
      |> Ecto.Changeset.change(name: site.name, title: site.name, title_prefix: nil)
      |> Repo.update!()
    end

    unless Repo.get_by(Sites.SEO, language: language) do
      Sites.create_default_seo(language)
    end
  end
end
