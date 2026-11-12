defmodule Brando.Tenant.Seeder do
  @moduledoc """
  Default initial-content seeder for a newly provisioned site.

  Brando can create the shared identity and SEO records for every configured
  language. Applications that also need a schema-specific home page or other
  initial content can configure a module implementing `c:seed/3` as
  `config :brando, tenant_seeder: MyApp.TenantSeeder`.
  """

  alias Brando.Environments.Environment
  alias Brando.Sites.Site
  alias Brando.Users.User

  @callback seed(Site.t(), Environment.t(), User.t()) :: :ok | {:error, term()}

  @behaviour __MODULE__

  @impl true
  def seed(%Site{} = site, %Environment{}, %User{}) do
    # The default identity's name is a placeholder, and in `:multi` the
    # identity's name is what the site's pages go by (`Brando.Sites.site_name/1`).
    Enum.each(site.languages, fn language ->
      language
      |> Brando.Sites.create_default_identity()
      |> Ecto.Changeset.change(name: site.name)
      |> Brando.Repo.update!()

      Brando.Sites.create_default_seo(language)
    end)

    :ok
  rescue
    exception -> {:error, exception}
  end
end
