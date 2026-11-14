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

  alias Brando.Tenant.Registry
  alias Brando.Users.User

  @doc """
  Provisions the configured site, with `creator` as its creator.

  Returns `{:created, site}`, `{:exists, site}` when a site with the key is
  already registered (it is left as it is), `{:error, reason}` when
  provisioning fails (nothing of the site is left), or `:not_single` outside
  `tenancy_mode: :single`, where it does nothing.
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
      key when is_binary(key) and key != "" ->
        case Registry.get_site_by_key(key) do
          nil -> with {:ok, site} <- Brando.Tenant.Setup.create_site(attrs(key), creator), do: {:created, site}
          site -> {:exists, site}
        end

      _missing ->
        {:error, :missing_site_key}
    end
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
