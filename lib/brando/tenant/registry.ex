defmodule Brando.Tenant.Registry do
  @moduledoc """
  Mutation boundary for Brando's public site and environment registry.

  All writes pass through this module so successful mutations refresh the
  read-optimized tenant cache. The registry schemas themselves are permanently
  stored in PostgreSQL's `public` schema.

  ## Binding a host

  An environment's `domain` decides which site answers on a host, so changing
  it is the installation's decision, not one site's. `create_environment/3`
  and `update_environment/3` refuse a change to it unless `:actor` is an
  installation superuser (`Brando.Authorization.Boundary.superuser?/1`), or
  `:system` for trusted maintenance code. With no `:actor` the change is
  refused too. `Brando.Environments.set_live/2` moves a dynamically delivered
  site's host between its own environments without one: the host is already
  the site's.

  An environment's `redirect_hosts` bind hosts as `domain` does, and the same
  check guards them; a live switch moves them with the domain.
  """

  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Environments.Environment
  alias Brando.Repo
  alias Brando.Sites.Site
  alias Brando.Tenant.Cache

  @public_opts [prefix: "public"]

  @spec list_sites() :: [Site.t()]
  def list_sites do
    # In the order they were created, not Postgres' physical order, which moves
    query = from(site in Site, order_by: [asc: site.id])

    query
    |> Repo.all(@public_opts)
    |> Repo.preload([environments: from(environment in Environment, order_by: [asc: environment.id])], @public_opts)
  end

  @spec get_site(pos_integer()) :: Site.t() | nil
  def get_site(id) do
    Site
    |> Repo.get(id, @public_opts)
    |> preload_environments()
  end

  @spec get_site_by_key(String.t()) :: Site.t() | nil
  def get_site_by_key(key) do
    from(site in Site, where: site.key == ^key)
    |> Repo.one(@public_opts)
    |> preload_environments()
  end

  @spec create_site(map()) :: {:ok, Site.t()} | {:error, Ecto.Changeset.t()}
  def create_site(attrs) do
    %Site{}
    |> Site.changeset(attrs, lookup_host: true)
    |> Repo.insert(@public_opts)
    |> refresh_cache_on_success()
  end

  @doc """
  Updates `site`'s row.

  When the change adds languages to the site, each of its environments is
  given its starting content in them once the row is committed
  (`Brando.Worker.SiteLanguageSeed`), named as created by `:creator`, the
  user making the change. A language removed deletes nothing: its content
  stays, and is used again when the language is added back. A change of the
  default language syncs each environment's identifiers.

  A new default language that the same change adds is seeded in every
  environment before the row is written instead, so the site's `/` has its
  homepage as soon as it moves there. When an environment cannot be seeded
  the row is left as it was and the changeset names the environment on
  `:default_language`; what the other environments got stays, unseen until
  the language is the site's, and the next attempt leaves it alone.

  That seeding holds the site's environment-operation lock from reading its
  environments to writing the row. When a copy, restore or setup holds the
  lock, the save fails at once with a `:default_language` error instead of
  waiting for it.
  """
  @spec update_site(Site.t(), map(), keyword()) :: {:ok, Site.t()} | {:error, Ecto.Changeset.t()}
  def update_site(%Site{} = site, attrs, opts \\ []) do
    changeset = Site.changeset(site, attrs, lookup_host: true)

    case new_default_to_seed(site, changeset) do
      nil ->
        write_site(site, changeset, [], opts)

      language ->
        site.id
        |> Brando.Tenant.Lock.environment_operation_key()
        |> Brando.Tenant.Lock.try_with(fn -> seed_and_write(site, changeset, language, opts) end)
        |> busy_to_error(changeset)
    end
  end

  defp seed_and_write(site, changeset, language, opts) do
    with {:ok, seeded} <- seed_in_every_environment(site, changeset, language, opts[:creator]),
         do: write_site(site, changeset, seeded, opts)
  end

  defp write_site(site, changeset, seeded, opts) do
    result = changeset |> Repo.update(@public_opts) |> refresh_cache_on_success()
    if Map.has_key?(changeset.changes, :status), do: access_changed(result)
    if Map.has_key?(changeset.changes, :default_language), do: default_language_changed(result)

    if Map.has_key?(changeset.changes, :languages),
      do: languages_added(result, (site.languages || []) ++ seeded, opts[:creator])

    result
  end

  defp busy_to_error(:busy, changeset) do
    {:error,
     Ecto.Changeset.add_error(
       changeset,
       :default_language,
       gettext(
         "cannot be seeded now: the site is busy with a copy, restore or setup of an environment. Try again when it has finished."
       )
     )}
  end

  defp busy_to_error(result, _changeset), do: result

  # The new default, when the change adds it, is seeded before the row is
  # written: until a job seeded it, `/` would answer 404
  defp new_default_to_seed(site, %Ecto.Changeset{valid?: true, changes: %{default_language: language}} = changeset) do
    if Brando.Tenant.mode() == :multi and language not in (site.languages || []) and
         language in Ecto.Changeset.get_field(changeset, :languages),
       do: language
  end

  defp new_default_to_seed(_site, _changeset), do: nil

  # Runs holding the site's environment-operation lock, so the environments
  # read here are all there are until the row is written
  defp seed_in_every_environment(site, changeset, language, creator) do
    seed_site = %{Ecto.Changeset.apply_changes(changeset) | environments: list_environments(site.id)}

    case Brando.Worker.SiteLanguageSeed.creator(creator) do
      nil ->
        {:error,
         Ecto.Changeset.add_error(
           changeset,
           :default_language,
           gettext("cannot be seeded: the installation has no superuser to create its content as")
         )}

      creator ->
        case Brando.Worker.SiteLanguageSeed.seed_environments(seed_site, language, creator) do
          :ok -> {:ok, [language]}
          {:error, environment, reason} -> {:error, not_seeded(changeset, environment, reason)}
        end
    end
  end

  defp not_seeded(changeset, environment, reason) do
    reason =
      case reason do
        %{__exception__: true} = exception -> Exception.message(exception)
        reason when is_atom(reason) -> reason |> Atom.to_string() |> String.replace("_", " ")
        reason -> inspect(reason)
      end

    Ecto.Changeset.add_error(
      changeset,
      :default_language,
      gettext("could not be seeded in %{environment}, so nothing was saved: %{reason}",
        environment: environment.name,
        reason: reason
      )
    )
  end

  defp languages_added({:ok, %Site{id: id, languages: languages}}, previous, creator) do
    added = languages -- previous

    if added != [] and Brando.Tenant.mode() == :multi do
      Repo.after_commit({:site_language_seed, id, added}, fn -> seed_languages(id, added, creator) end, late: true)
    end
  end

  defp languages_added(_error, _previous, _creator), do: :ok

  defp seed_languages(site_id, languages, creator) do
    case get_site(site_id) do
      nil -> :ok
      site -> Enum.each(languages, &Brando.Worker.SiteLanguageSeed.enqueue(site, &1, creator))
    end
  end

  # On a multi-site installation the default language's entries have
  # unprefixed URLs, so the stored ones change with it: once the cache holds
  # the new default, each environment's identifiers are synced in a job.
  defp default_language_changed({:ok, %Site{id: id}}) do
    if Brando.Tenant.mode() == :multi do
      Repo.after_commit({:identifier_sync, id}, fn -> sync_identifiers(id) end, late: true)
    end
  end

  defp default_language_changed(_error), do: :ok

  defp sync_identifiers(site_id) do
    case get_site(site_id) do
      nil -> :ok
      site -> Brando.Worker.IdentifierSync.enqueue(site)
    end
  end

  @doc """
  Puts `site` in the provider library group `group`, or with `nil` or `""`
  takes it out (see `Brando.Videos.ProviderLibrary`). What another site may
  see of the provider accounts is the installation's decision: refused unless
  `actor` is an installation superuser, or `:system`.
  """
  @spec put_provider_library_group(Site.t(), String.t() | nil, term()) ::
          {:ok, Site.t()} | {:error, Ecto.Changeset.t()}
  def put_provider_library_group(%Site{} = site, group, actor) do
    changeset = Site.provider_library_group_changeset(site, group)

    if not is_nil(actor) and Boundary.superuser?(actor) do
      changeset |> Repo.update(@public_opts) |> refresh_cache_on_success()
    else
      {:error,
       Ecto.Changeset.add_error(
         changeset,
         :provider_library_group,
         gettext("Only a superuser can choose which sites share a provider library.")
       )}
    end
  end

  @spec delete_site(Site.t()) :: {:ok, Site.t()} | {:error, Ecto.Changeset.t()}
  def delete_site(%Site{} = site) do
    site
    |> Repo.delete(@public_opts)
    |> refresh_cache_on_success()
    |> tap(&access_changed/1)
  end

  @spec list_environments(Site.t() | pos_integer()) :: [Environment.t()]
  def list_environments(%Site{id: site_id}), do: list_environments(site_id)

  def list_environments(site_id) do
    from(environment in Environment,
      where: environment.site_id == ^site_id,
      order_by: [asc: environment.name, asc: environment.id]
    )
    |> Repo.all(@public_opts)
  end

  @spec get_environment(pos_integer()) :: Environment.t() | nil
  def get_environment(id), do: Repo.get(Environment, id, @public_opts)

  @spec get_environment_by_key(Site.t() | pos_integer(), String.t()) :: Environment.t() | nil
  def get_environment_by_key(%Site{id: site_id}, key), do: get_environment_by_key(site_id, key)

  def get_environment_by_key(site_id, key) do
    from(environment in Environment,
      where: environment.site_id == ^site_id and environment.key == ^key
    )
    |> Repo.one(@public_opts)
  end

  @spec create_environment(Site.t() | pos_integer(), map(), keyword()) ::
          {:ok, Environment.t()} | {:error, Ecto.Changeset.t()}
  def create_environment(site, attrs, opts \\ [])

  def create_environment(%Site{id: site_id}, attrs, opts), do: create_environment(site_id, attrs, opts)

  def create_environment(site_id, attrs, opts) do
    attrs = put_site_id(attrs, site_id)

    %Environment{}
    |> Environment.changeset(attrs)
    |> authorize_domain(opts[:actor])
    |> Repo.insert(@public_opts)
    |> refresh_cache_on_success()
  end

  @doc """
  Checks, before anything is written, what `create_environment/3` with
  `attrs` checks, and that no other environment binds its domain or any of
  its redirect hosts: `:ok`, or `{:error, changeset}` with the errors an
  insert would have.

  For a create that writes the row without its hosts and binds them with
  `bind_hosts/3` once the environment is ready: a host that is taken is
  refused before any work starts. A host bound by another write after this
  check is refused by `bind_hosts/3`.
  """
  @spec check_new_environment(Site.t() | pos_integer(), map(), keyword()) :: :ok | {:error, Ecto.Changeset.t()}
  def check_new_environment(site, attrs, opts \\ [])

  def check_new_environment(%Site{id: site_id}, attrs, opts), do: check_new_environment(site_id, attrs, opts)

  def check_new_environment(site_id, attrs, opts) do
    %Environment{}
    |> Environment.changeset(put_site_id(attrs, site_id))
    |> authorize_domain(opts[:actor])
    |> refuse_bound_hosts()
    |> Ecto.Changeset.apply_action(:insert)
    |> case do
      {:ok, _environment} -> :ok
      {:error, _changeset} = error -> error
    end
  end

  defp refuse_bound_hosts(%Ecto.Changeset{valid?: true} = changeset) do
    domain = Ecto.Changeset.get_field(changeset, :domain)
    redirect_hosts = Ecto.Changeset.get_field(changeset, :redirect_hosts) || []

    changeset
    |> refuse_bound(:domain, List.wrap(domain), gettext("Another environment already uses this host."))
    |> refuse_bound(
      :redirect_hosts,
      redirect_hosts,
      gettext("Another environment already uses one of these hosts, as its domain or a redirect host.")
    )
  end

  defp refuse_bound_hosts(changeset), do: changeset

  defp refuse_bound(changeset, _field, [], _message), do: changeset

  defp refuse_bound(changeset, field, hosts, message) do
    bound? =
      from(environment in Environment,
        where: environment.domain in ^hosts or fragment("? && ?::varchar[]", environment.redirect_hosts, ^hosts),
        select: true,
        limit: 1
      )
      |> Repo.one(@public_opts)

    if bound? == true, do: Ecto.Changeset.add_error(changeset, field, message), else: changeset
  end

  @doc """
  Binds `attrs`' `domain` and `redirect_hosts` to an environment written
  without them, checking `opts[:actor]`'s authority to bind them as
  `create_environment/3` does: the last step of a create, once the
  environment's schema is ready, so its hosts resolve only from then on. A
  host another write bound meanwhile is refused with `{:error, changeset}`.
  With no host in `attrs`, nothing is written. Binding a live environment's
  domain renders the site's stored public URLs again, as
  `update_environment/3` does.
  """
  @spec bind_hosts(Environment.t(), map(), keyword()) :: {:ok, Environment.t()} | {:error, Ecto.Changeset.t()}
  def bind_hosts(%Environment{} = environment, attrs, opts \\ []) do
    attrs = Map.take(attrs, [:domain, :redirect_hosts, "domain", "redirect_hosts"])

    case environment |> Environment.changeset(attrs) |> authorize_domain(opts[:actor]) do
      %Ecto.Changeset{valid?: true, changes: changes} when changes == %{} ->
        {:ok, environment}

      changeset ->
        changeset
        |> Repo.update(@public_opts)
        |> refresh_cache_on_success()
        |> rerender_on_public_domain_change(changeset)
    end
  end

  @doc """
  Releases an environment's domain and redirect hosts, so they resolve to no
  environment once the write is committed and the cache refreshed: the first
  step of removing the environment. Releasing a host needs no authority to
  bind one. With no host bound, nothing is written.
  """
  @spec unbind_hosts(Environment.t()) :: {:ok, Environment.t()} | {:error, Ecto.Changeset.t()}
  def unbind_hosts(%Environment{domain: nil, redirect_hosts: hosts} = environment) when hosts in [nil, []],
    do: {:ok, environment}

  def unbind_hosts(%Environment{} = environment) do
    environment
    |> Ecto.Changeset.change(domain: nil, redirect_hosts: [])
    |> Repo.update(@public_opts)
    |> refresh_cache_on_success()
  end

  @doc """
  Updates an environment, checking `opts[:actor]`'s authority to bind its
  hosts. Once the change is committed, the site's open environments screens
  are told (`Brando.Environments.announce/1`).
  """
  @spec update_environment(Environment.t(), map(), keyword()) ::
          {:ok, Environment.t()} | {:error, Ecto.Changeset.t()}
  def update_environment(%Environment{} = environment, attrs, opts \\ []) do
    changeset =
      environment
      |> Environment.changeset(attrs)
      |> authorize_domain(opts[:actor])

    changeset
    |> Repo.update(@public_opts)
    |> refresh_cache_on_success()
    |> rerender_on_public_domain_change(changeset)
    |> announce_on_success()
  end

  defp announce_on_success({:ok, %Environment{site_id: site_id}} = result) do
    Repo.after_commit({:environments_updated, site_id}, fn -> announce(site_id) end)
    result
  end

  defp announce_on_success(result), do: result

  # The key the hosts trigger on `public.environments` locks with; the
  # migrations that define the trigger spell it out as well
  @hosts_lock_key "brando.environments.hosts"

  @doc false
  # Takes, for the rest of the caller's transaction, the advisory lock the
  # hosts trigger takes before it checks a binding
  @spec lock_hosts() :: :ok
  def lock_hosts do
    Ecto.Adapters.SQL.query!(Repo.repo(), "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [@hosts_lock_key])
    :ok
  end

  # Outside `Repo.transaction/2` (a data migration, a task) this runs at once,
  # in the caller's transaction, where a raise would roll the write back
  defp announce(site_id) do
    Brando.Environments.announce(site_id)
  rescue
    # No PubSub registry under that name
    ArgumentError -> :ok
  end

  @spec delete_environment(Environment.t()) ::
          {:ok, Environment.t()} | {:error, Ecto.Changeset.t()}
  def delete_environment(%Environment{} = environment) do
    environment
    |> Repo.delete(@public_opts)
    |> refresh_cache_on_success()
  end

  defp rerender_on_public_domain_change({:ok, %Environment{live: true, site_id: site_id}} = result, %{
         changes: %{domain: _domain}
       }) do
    rerender_public_urls_after_commit(site_id)
    result
  end

  defp rerender_on_public_domain_change(result, _changeset), do: result

  @doc """
  Renders again, in every environment of the site `site_id`, the entries
  whose stored HTML names the site's public base URL, its live environment's
  domain (`Brando.Content.Blocks.rerender_public_urls/2`): for a write that
  changes that domain. Queued once the transaction around the caller has
  committed and this node's cache holds the write; what fails there is
  logged and leaves the write as it is.
  """
  @spec rerender_public_urls_after_commit(pos_integer()) :: :ok
  def rerender_public_urls_after_commit(site_id),
    do: Repo.after_commit({:public_url_rerender, site_id}, fn -> rerender_public_urls(site_id) end, late: true)

  defp rerender_public_urls(site_id) do
    case get_site(site_id) do
      nil -> :ok
      site -> Brando.Content.Blocks.rerender_public_urls(site.key, site.environments)
    end
  end

  defp authorize_domain(changeset, actor) do
    if binds_hosts?(actor) do
      changeset
    else
      changeset
      |> refuse_host_change(:domain, gettext("Only a superuser can change the host an environment answers on."))
      |> refuse_host_change(
        :redirect_hosts,
        gettext("Only a superuser can change the hosts that redirect to an environment.")
      )
    end
  end

  defp refuse_host_change(changeset, field, message) do
    if Map.has_key?(changeset.changes, field),
      do: Ecto.Changeset.add_error(changeset, field, message),
      else: changeset
  end

  defp binds_hosts?(nil), do: false
  defp binds_hosts?(actor), do: Boundary.superuser?(actor)

  defp preload_environments(nil), do: nil

  defp preload_environments(%Site{} = site),
    do: Repo.preload(site, :environments, @public_opts)

  defp put_site_id(attrs, site_id) do
    if Enum.all?(Map.keys(attrs), &is_binary/1) do
      Map.put(attrs, "site_id", site_id)
    else
      Map.put(attrs, :site_id, site_id)
    end
  end

  # Inside a transaction, after it commits (`Cache.invalidate/0`)
  defp refresh_cache_on_success({:ok, _record} = result) do
    Cache.invalidate()
    result
  end

  defp refresh_cache_on_success({:error, _changeset} = result), do: result

  # Who may enter a site follows its status: open channels check again.
  defp access_changed({:ok, _site}), do: Brando.Authorization.Realtime.broadcast_changed()
  defp access_changed(_error), do: :ok
end
