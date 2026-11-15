defmodule Brando.Worker.SiteLanguageSeed do
  @moduledoc """
  Gives one of a site's environments its starting content in a language just
  added to the site (`Brando.Tenant.Seeder.seed_added_language/4`). Queued
  for each environment of the site once the site row is committed
  (`Brando.Tenant.Registry.update_site/3`), so a slow or failing environment
  neither holds up the save nor the other environments.

  Content already in that language is left alone, so the job can run again:
  a failed attempt is retried, and the sites screen offers to queue it again
  for an environment that still has no identity in the language.

  The seeded content names the user who added the language as its creator,
  or the installation's oldest superuser (`Brando.Setup.Account.superuser/0`)
  when it was added with no user or that user is gone.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      period: :infinity,
      keys: [:tenant_prefix, :language],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Brando.Sites.Site
  alias Brando.Tenant.Job, as: TenantJob

  @doc """
  Queues the seeding of `language` in each of `site`'s environments, or in
  the one given as `:environment`, with `creator` (a user or `nil`) as the
  creator of what it seeds.
  """
  @spec enqueue(Site.t(), String.t(), Brando.Users.User.t() | nil, keyword()) :: :ok
  def enqueue(%Site{environments: environments} = site, language, creator, opts \\ [])
      when is_list(environments) and is_binary(language) do
    environments = if opts[:environment], do: [opts[:environment]], else: environments

    for environment <- environments do
      %{
        "tenant_prefix" => Brando.Tenant.prefix(site, environment),
        "language" => language,
        "user_id" => creator && creator.id
      }
      |> new()
      |> Oban.insert()
    end

    :ok
  end

  @doc """
  Seeds `language` in each of `site`'s environments now, the live one first,
  holding the site's environment-operation lock so no copy runs between
  them. Returns the first environment that failed, with the reason; those
  seeded before it keep their content. `site` is the site as it will be
  stored, with `language` among its languages.
  """
  @spec seed_environments(Site.t(), String.t(), Brando.Users.User.t()) ::
          :ok | {:error, Brando.Environments.Environment.t(), term()}
  def seed_environments(%Site{environments: environments} = site, language, creator) when is_list(environments) do
    Brando.Environments.with_site_lock(site, fn ->
      environments
      |> Enum.sort_by(&{not &1.live, &1.name})
      |> Enum.find_value(:ok, fn environment ->
        case seed_in(site, environment, language, creator) do
          :ok -> nil
          {:error, reason} -> {:error, environment, reason}
        end
      end)
    end)
  end

  defp seed_in(site, environment, language, creator) do
    Brando.Tenant.with_prefix(Brando.Tenant.prefix(site, environment), fn ->
      seed(site, environment, language, creator)
    end)
  rescue
    exception -> {:error, exception}
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"tenant_prefix" => prefix, "language" => language} = args} = job) do
    # Rendering the seeded entries builds their URLs from the site's
    # languages in the tenant cache, which on this node may not have seen the
    # new ones yet
    Brando.Tenant.Cache.warm()

    case site_environment(prefix) do
      nil ->
        # Deleted since the job was queued: its schema is gone with it
        {:cancel, :environment_gone}

      {site, environment} ->
        if language in site.languages,
          do: seed_as_creator(job, site, environment, language, creator(args["user_id"])),
          else: {:cancel, :language_removed}
    end
  end

  defp seed_as_creator(_job, _site, _environment, _language, nil), do: {:cancel, :no_creator}

  defp seed_as_creator(job, site, environment, language, creator),
    do: TenantJob.run(job, fn -> seed(site, environment, language, creator) end)

  # The admin's scope does not decide what the seeder may write, as when the
  # site was provisioned (`Brando.Tenant.Setup`)
  defp seed(site, environment, language, creator) do
    Brando.Authorization.Boundary.with_scope(nil, fn ->
      Brando.Tenant.Seeder.seed_added_language(site, environment, language, creator)
    end)
  end

  @doc false
  # The user a seeding names as creator: the one given while active, or the
  # installation's oldest superuser
  def creator(nil), do: Brando.Setup.Account.superuser()

  def creator(%Brando.Users.User{id: user_id}), do: creator(user_id)

  def creator(user_id) do
    case Brando.Repo.get(Brando.Users.User, user_id) do
      %Brando.Users.User{deleted_at: nil, active: true} = user -> user
      _gone -> Brando.Setup.Account.superuser()
    end
  end

  # The site as stored now, with the environment the prefix names
  defp site_environment(prefix) do
    Enum.find_value(Brando.Tenant.Registry.list_sites(), fn site ->
      case Enum.find(site.environments, &(Brando.Tenant.prefix(site, &1) == prefix)) do
        nil -> nil
        environment -> {site, environment}
      end
    end)
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)
end
