defmodule Brando.Tenant.Seeder do
  @moduledoc """
  Default initial-content seeder for a newly provisioned site.

  Provisioning runs it in the site's Production environment, which Staging is
  then copied from. For each of the site's languages it creates an identity
  named after the site and an SEO record, and then what `mix brando.setup`
  seeds for a single-site installation (`Brando.Setup.Seeds`): the modules, a
  published homepage built from them, the footer fragment and a main menu.

  An application configures its own seeder, a module implementing `c:seed/3`,
  as `config :brando, tenant_seeder: MyApp.TenantSeeder`. It replaces this
  one: call `seed/3` from it to keep this content, or create the identity and
  SEO records yourself.
  """

  alias Brando.Environments.Environment
  alias Brando.Sites.Site
  alias Brando.Users.User

  @callback seed(Site.t(), Environment.t(), User.t()) :: :ok | {:error, term()}

  @behaviour __MODULE__

  @impl true
  def seed(%Site{} = site, %Environment{}, %User{} = creator) do
    languages = Enum.map(site.languages, &String.to_existing_atom/1)

    # The default identity's name is a placeholder, and in `:multi` the
    # identity's name is what the site's pages go by (`Brando.Sites.site_name/1`).
    Enum.each(languages, fn language ->
      language
      |> Brando.Sites.create_default_identity()
      |> Ecto.Changeset.change(name: site.name)
      |> Brando.Repo.update!()

      Brando.Sites.create_default_seo(language)
    end)

    {:ok, _report} = Brando.Setup.Seeds.run(creator, languages: languages)
    :ok
  rescue
    exception -> {:error, exception}
  end
end
