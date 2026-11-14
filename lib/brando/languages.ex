defmodule Brando.Languages do
  @moduledoc """
  The content languages in use, and the default one.

  Two lists, with different jobs:

    * the installation's languages, `config :brando, languages:` and
      `config :brando, default_language:`: what the installation can hold. The
      `language` type accepts these, a site is checked against them, and every
      language's label (`text:`) comes from here;
    * a site's languages, `sites.languages` and `sites.default_language`: what
      that site uses, a subset of the installation's.

  `languages/0` and `default_language/0` answer for the site the process works
  for in multi-site mode (`Brando.Tenant`), and for the installation otherwise:
  with tenancy off or in single-site mode, and in multi-site mode outside every
  site (a mix task, a job with no tenant, a screen that is not about one site).

  They are read on every request and render, so they never query the database:
  the site comes from `Brando.Tenant.Cache`. This module is a leaf that only
  reads the application env, the process dictionary and `:persistent_term`, so
  low-level rendering modules can call it without pulling the rest of Brando
  into their compile graph.
  """

  require Logger

  alias Brando.RuntimeConfig

  # Kept in step with `Brando.Tenant` and `Brando.Tenant.Cache`; read here
  # directly so this module stays a leaf. An atom, not the alias: the alias
  # would make `Brando.Tenant` a dependency.
  @process_prefix_key {:"Elixir.Brando.Tenant", :current_prefix}

  @type language :: [value: String.t(), text: String.t()]

  @doc """
  The languages in use, as `[[value: "en", text: "English"], …]`: the current
  site's in its own order, else the installation's.
  """
  @spec languages() :: [language()]
  def languages, do: languages(current_site())

  @doc """
  The languages `site` uses, in its own order, labelled from the installation's
  list. A language the installation does not configure is left out. With `nil`,
  the installation's list.
  """
  @spec languages(map() | nil) :: [language()]
  def languages(nil), do: installation_languages()

  def languages(%{languages: site_languages}) when is_list(site_languages) do
    installation = installation_languages()
    by_code = Map.new(installation, &{to_string(&1[:value]), &1})

    case site_languages |> Enum.map(&Map.get(by_code, to_string(&1))) |> Enum.reject(&is_nil/1) do
      [] -> installation
      languages -> languages
    end
  end

  def languages(_site), do: installation_languages()

  @doc "The codes of `languages/0`, as strings."
  @spec codes() :: [String.t()]
  def codes, do: codes(current_site())

  @doc "The codes of `languages/1`, as strings."
  @spec codes(map() | nil) :: [String.t()]
  def codes(site), do: site |> languages() |> Enum.map(&to_string(&1[:value]))

  @doc """
  The default language: the current site's `default_language`, else the
  installation's.
  """
  @spec default_language() :: String.t() | nil
  def default_language, do: default_language(current_site())

  @doc """
  `site`'s default language. When the installation does not configure it, the
  first of the site's languages that it does. With `nil`, the installation's.
  """
  @spec default_language(map() | nil) :: String.t() | nil
  def default_language(nil), do: installation_default_language()

  def default_language(%{languages: site_languages} = site) when is_list(site_languages) do
    codes = codes(site)
    default = site |> Map.get(:default_language) |> then(&(&1 && to_string(&1)))

    cond do
      default in codes -> default
      to_string(installation_default_language()) in codes -> installation_default_language()
      true -> List.first(codes)
    end
  end

  def default_language(_site), do: installation_default_language()

  @doc "Whether `language` is one of `languages/0`."
  @spec member?(term()) :: boolean()
  def member?(language), do: to_string(language) in codes()

  @doc """
  The installation's languages, `config :brando, languages:`. For what stays
  on the installation's list whatever the site: the `language` type, mix
  tasks, and the check a site goes through.
  """
  @spec installation_languages() :: [language()]
  def installation_languages, do: RuntimeConfig.get(:languages) || []

  @doc "The codes of `installation_languages/0`, as strings."
  @spec installation_codes() :: [String.t()]
  def installation_codes, do: Enum.map(installation_languages(), &to_string(&1[:value]))

  @doc "The installation's default language, `config :brando, default_language:`."
  @spec installation_default_language() :: String.t() | nil
  def installation_default_language, do: RuntimeConfig.get(:default_language)

  @doc "The languages `site` lists that the installation does not configure."
  @spec unconfigured(map()) :: [String.t()]
  def unconfigured(%{languages: site_languages}) when is_list(site_languages) do
    installation = installation_codes()
    site_languages |> Enum.map(&to_string/1) |> Enum.reject(&(&1 in installation))
  end

  def unconfigured(_site), do: []

  @doc """
  Logs a warning for each language `site` lists that the installation does not
  configure. Those are left out of the site's languages. Called when the
  tenant cache loads the site.
  """
  @spec warn_unconfigured(map()) :: :ok
  def warn_unconfigured(site) do
    case unconfigured(site) do
      [] ->
        :ok

      languages ->
        Logger.warning(
          "Site #{inspect(Map.get(site, :key))} lists #{Enum.map_join(languages, ", ", &inspect/1)}, " <>
            "which `config :brando, :languages` does not configure. Left out of the site's languages."
        )
    end
  end

  # The site the process works for, in multi-site mode only: from the tenant
  # prefix, read from the tenant cache.
  defp current_site do
    with :multi <- RuntimeConfig.get(:tenancy_mode),
         "tenant_" <> remainder <- Process.get(@process_prefix_key),
         [site_key, _environment_key] <- String.split(remainder, "_", parts: 2) do
      :persistent_term.get({:brando, :site, site_key}, nil)
    else
      _ -> nil
    end
  end
end
