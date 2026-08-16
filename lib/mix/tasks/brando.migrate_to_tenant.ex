defmodule Mix.Tasks.Brando.MigrateToTenant do
  @shortdoc "Copies an existing public-schema installation into a new tenant site"

  @moduledoc """
  Migrates existing public content into a new site's Production schema, then
  creates Staging as a complete copy.

      mix brando.migrate_to_tenant --site-key=my-site
      mix brando.migrate_to_tenant --site-key=my-site --name="My Site" --creator-email=admin@example.com

  Global users, sessions, tenant registry rows, Oban jobs, and asset-set
  metadata remain in `public` and are never copied into the tenant schema.
  """

  use Mix.Task

  import Ecto.Query, only: [from: 2]

  alias Brando.Users.User

  @switches [site_key: :string, name: :string, creator_email: :string]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _remaining, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [], do: Mix.raise("Invalid options: #{inspect(invalid)}")

    site_key = opts[:site_key] || Mix.raise("--site-key is required")
    name = opts[:name] || site_key |> String.replace("-", " ") |> String.capitalize()
    creator = creator!(opts[:creator_email])
    languages = configured_languages()
    default_language = Brando.config(:default_language) |> to_string()

    attrs = %{
      name: name,
      key: site_key,
      languages: languages,
      default_language: default_language,
      status: :active,
      delivery_mode: :dynamic
    }

    case Brando.Tenant.Migration.migrate_public(attrs, creator) do
      {:ok, site} ->
        Mix.shell().info("Migrated public content into site #{site.key} with Production and Staging environments")

      {:error, reason} ->
        Mix.raise("Tenant migration failed: #{inspect(reason)}")
    end
  end

  defp creator!(nil) do
    from(user in User,
      where: user.role == :superuser and user.active,
      order_by: [asc: user.id],
      limit: 1
    )
    |> Brando.Repo.one(prefix: "public")
    |> case do
      %User{} = user -> user
      nil -> Mix.raise("No active superuser exists; pass --creator-email")
    end
  end

  defp creator!(email) do
    from(user in User, where: user.email == ^email and user.active)
    |> Brando.Repo.one(prefix: "public")
    |> case do
      %User{} = user -> user
      nil -> Mix.raise("No active user found for --creator-email=#{email}")
    end
  end

  defp configured_languages do
    Brando.config(:languages)
    |> List.wrap()
    |> Enum.map(fn
      options when is_list(options) -> options[:value]
      %{value: value} -> value
      language -> language
    end)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
    |> case do
      [] -> [Brando.config(:default_language) |> to_string()]
      languages -> languages
    end
  end
end
