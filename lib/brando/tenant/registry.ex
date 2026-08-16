defmodule Brando.Tenant.Registry do
  @moduledoc """
  Mutation boundary for Brando's public site and environment registry.

  All writes pass through this module so successful mutations refresh the
  read-optimized tenant cache. The registry schemas themselves are permanently
  stored in PostgreSQL's `public` schema.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Environments.Environment
  alias Brando.Repo
  alias Brando.Sites.Site
  alias Brando.Tenant.Cache

  @spec list_sites() :: [Site.t()]
  def list_sites do
    Site
    |> Repo.all()
    |> Repo.preload(:environments)
  end

  @spec get_site(pos_integer()) :: Site.t() | nil
  def get_site(id) do
    Site
    |> Repo.get(id)
    |> preload_environments()
  end

  @spec get_site_by_key(String.t()) :: Site.t() | nil
  def get_site_by_key(key) do
    from(site in Site, where: site.key == ^key)
    |> Repo.one()
    |> preload_environments()
  end

  @spec create_site(map()) :: {:ok, Site.t()} | {:error, Ecto.Changeset.t()}
  def create_site(attrs) do
    %Site{}
    |> Site.changeset(attrs)
    |> Repo.insert()
    |> refresh_cache_on_success()
  end

  @spec update_site(Site.t(), map()) :: {:ok, Site.t()} | {:error, Ecto.Changeset.t()}
  def update_site(%Site{} = site, attrs) do
    site
    |> Site.changeset(attrs)
    |> Repo.update()
    |> refresh_cache_on_success()
  end

  @spec delete_site(Site.t()) :: {:ok, Site.t()} | {:error, Ecto.Changeset.t()}
  def delete_site(%Site{} = site) do
    site
    |> Repo.delete()
    |> refresh_cache_on_success()
  end

  @spec list_environments(Site.t() | pos_integer()) :: [Environment.t()]
  def list_environments(%Site{id: site_id}), do: list_environments(site_id)

  def list_environments(site_id) do
    from(environment in Environment,
      where: environment.site_id == ^site_id,
      order_by: [asc: environment.name, asc: environment.id]
    )
    |> Repo.all()
  end

  @spec get_environment(pos_integer()) :: Environment.t() | nil
  def get_environment(id), do: Repo.get(Environment, id)

  @spec get_environment_by_key(Site.t() | pos_integer(), String.t()) :: Environment.t() | nil
  def get_environment_by_key(%Site{id: site_id}, key), do: get_environment_by_key(site_id, key)

  def get_environment_by_key(site_id, key) do
    from(environment in Environment,
      where: environment.site_id == ^site_id and environment.key == ^key
    )
    |> Repo.one()
  end

  @spec create_environment(Site.t() | pos_integer(), map()) ::
          {:ok, Environment.t()} | {:error, Ecto.Changeset.t()}
  def create_environment(%Site{id: site_id}, attrs), do: create_environment(site_id, attrs)

  def create_environment(site_id, attrs) do
    attrs = put_site_id(attrs, site_id)

    %Environment{}
    |> Environment.changeset(attrs)
    |> Repo.insert()
    |> refresh_cache_on_success()
  end

  @spec update_environment(Environment.t(), map()) ::
          {:ok, Environment.t()} | {:error, Ecto.Changeset.t()}
  def update_environment(%Environment{} = environment, attrs) do
    environment
    |> Environment.changeset(attrs)
    |> Repo.update()
    |> refresh_cache_on_success()
  end

  @spec delete_environment(Environment.t()) ::
          {:ok, Environment.t()} | {:error, Ecto.Changeset.t()}
  def delete_environment(%Environment{} = environment) do
    environment
    |> Repo.delete()
    |> refresh_cache_on_success()
  end

  defp preload_environments(nil), do: nil
  defp preload_environments(%Site{} = site), do: Repo.preload(site, :environments)

  defp put_site_id(attrs, site_id) do
    if Enum.all?(Map.keys(attrs), &is_binary/1) do
      Map.put(attrs, "site_id", site_id)
    else
      Map.put(attrs, :site_id, site_id)
    end
  end

  defp refresh_cache_on_success({:ok, _record} = result) do
    Cache.invalidate()
    result
  end

  defp refresh_cache_on_success({:error, _changeset} = result), do: result
end
