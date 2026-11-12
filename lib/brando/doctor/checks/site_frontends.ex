defmodule Brando.Doctor.Checks.SiteFrontends do
  @moduledoc """
  With `tenancy_mode: :multi` and a non-empty `config :brando, site_frontends`
  (`Brando.Site.Frontend`): the active sites, or environments, without an
  entry, whose pages answer 404 and cannot be previewed, and the entries that
  name no site or environment.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Context
  alias Brando.Tenant

  @impl true
  def id, do: "site_frontends"

  @impl true
  def label, do: dgettext("doctor", "Sites without a frontend")

  @impl true
  def run(%Context{} = context) do
    frontends = Brando.config(:site_frontends) || %{}

    if Tenant.mode() == :multi and is_map(frontends) and map_size(frontends) > 0 do
      sites = Tenant.Registry.list_sites()
      evaluate(sites, Map.keys(frontends), checked_site_keys(context, sites))
    else
      skipped(dgettext("doctor", "only with tenancy_mode :multi and site_frontends"))
    end
  end

  # The admin checks the site it runs in; the terminal every site.
  defp checked_site_keys(%Context{mode: :admin, prefix: prefix}, _sites), do: [Tenant.site_key_of(prefix)]
  defp checked_site_keys(_context, sites), do: Enum.map(sites, & &1.key)

  @doc """
  Turns the sites (`Brando.Sites.Site` structs with their environments), the
  `site_frontends` keys and the keys of the sites to check for a frontend into
  a result.
  """
  def evaluate(sites, keys, checked_site_keys) do
    missing =
      for site <- sites, site.status == :active, site.key in checked_site_keys, item <- missing(site, keys), do: item

    unknown = Enum.reject(keys, &names_site?(&1, sites))

    items =
      Enum.map(missing, &dgettext("doctor", "%{site}: no frontend", site: &1)) ++
        Enum.map(unknown, &dgettext("doctor", "%{key}: names no site", key: describe(&1)))

    cond do
      items == [] ->
        ok(dgettext("doctor", "every active site has a frontend"))

      missing == [] ->
        warning(
          dngettext(
            "doctor",
            "%{count} site_frontends entry names no site",
            "%{count} site_frontends entries name no site",
            length(unknown)
          ),
          fix: dgettext("doctor", "remove the entry, or correct its site key, in config :brando, site_frontends"),
          items: items
        )

      true ->
        warning(
          dngettext(
            "doctor",
            "%{count} site without a frontend: its pages answer 404 and cannot be previewed",
            "%{count} sites without a frontend: their pages answer 404 and cannot be previewed",
            length(missing)
          ),
          fix:
            dgettext(
              "doctor",
              "generate one with mix brando.gen.site --site KEY, or register the module that renders the site in config :brando, site_frontends"
            ),
          items: items
        )
    end
  end

  # A site with an entry of its own, or for each of its environments, has one.
  defp missing(site, keys) do
    without = Enum.reject(site.environments, &({site.key, &1.key} in keys))

    cond do
      site.key in keys -> []
      length(without) == length(site.environments) -> [site.key]
      true -> Enum.map(without, &"#{site.key}/#{&1.key}")
    end
  end

  defp names_site?({site_key, environment_key}, sites),
    do: Enum.any?(sites, &(&1.key == site_key and Enum.any?(&1.environments, fn env -> env.key == environment_key end)))

  defp names_site?(site_key, sites), do: Enum.any?(sites, &(&1.key == site_key))

  defp describe({site_key, environment_key}), do: "#{site_key}/#{environment_key}"
  defp describe(site_key), do: to_string(site_key)
end
