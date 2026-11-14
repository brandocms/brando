defmodule Brando.Setup.Site do
  @moduledoc """
  The one site of a `tenancy_mode: :single` installation, which
  `mix brando.setup` provisions after it has created the first account.

  The site takes its key from `config :brando, site_key:`, its name from
  `config :brando, app_name:` (what setup names the identity without tenancy),
  and its languages and default language from the installation's
  `:languages` and `:default_language`. It is active and delivered
  dynamically. `Brando.Tenant.Setup.create_site/3` provisions it with live
  Production and Staging, and the configured seeder gives Production its
  content. The environments get no domain: a `:single` installation answers
  every host from the site's live environment.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Tenant.Registry
  alias Brando.Users.User

  @doc """
  Provisions the configured site, with `creator` as its creator.

  Returns `{:created, site}`, `{:exists, site}` when a site with the key is
  already registered (it is left as it is), `{:error, reason}`, or
  `:not_single` outside `tenancy_mode: :single`, where it does nothing.

  The errors that are not `Brando.Tenant.Setup.create_site/3`'s own:
  `:missing_site_key`; `:public_holds_content`, when the installation's pages
  are still in `public` and `mix brando.migrate_to_tenant` is what creates the
  site; and `{:incomplete_site, key}`, when the registered site has no live
  environment.
  """
  @spec provision(User.t()) ::
          {:created, Brando.Sites.Site.t()}
          | {:exists, Brando.Sites.Site.t()}
          | {:error, term()}
          | :not_single
  def provision(%User{} = creator) do
    if Brando.Tenant.mode() == :single, do: provision_single(creator), else: :not_single
  end

  defp provision_single(creator) do
    case Brando.config(:site_key) do
      key when is_binary(key) and key != "" -> provision_key(key, creator)
      _missing -> {:error, :missing_site_key}
    end
  end

  defp provision_key(key, creator) do
    case Registry.get_site_by_key(key) do
      nil -> create(key, creator)
      site -> existing(site)
    end
  end

  # An installation switched to `:single` serves from `public` until
  # `mix brando.migrate_to_tenant` moves its content into the site. A seeded
  # site would take the hosts over and leave that content unreachable.
  defp create(key, creator) do
    if public_pages?() do
      {:error, :public_holds_content}
    else
      with {:ok, site} <- Brando.Tenant.Setup.create_site(attrs(key), creator), do: {:created, site}
    end
  end

  defp public_pages? do
    Brando.Repo.all(from(page in Brando.Pages.Page, select: page.id, limit: 1), prefix: "public") != []
  end

  # A site with no live environment is what a failed run left when its
  # cleanup failed too: it has no content, and is not one to keep
  defp existing(site) do
    if Enum.any?(site.environments, & &1.live), do: {:exists, site}, else: {:error, {:incomplete_site, site.key}}
  end

  @doc "The attributes the site is created with."
  @spec attrs(String.t()) :: map()
  def attrs(key) do
    languages = Enum.map(Brando.config(:languages) || [], &to_string(&1[:value]))

    %{
      name: name(),
      key: key,
      languages: languages,
      default_language: to_string(Brando.config(:default_language) || List.first(languages)),
      status: :active,
      delivery_mode: :dynamic
    }
  end

  defp name do
    case Brando.config(:app_name) do
      name when is_binary(name) and name != "" -> name
      _ -> "Brando"
    end
  end
end
