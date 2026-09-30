defmodule Brando.Trait.Translatable.RuntimeConfig do
  @moduledoc """
  The translation config of a Blueprint declared with `runtime_config: true`,
  such as Brando's own Page, read from the application's config when called:

      config :brando, Brando.Pages.Page,
        translatable: [mode: :synchronized, source_controlled_fields: [:template]],
        # Optional, per site key in a tenant installation; replaces the above
        translatable_sites: %{"acme" => [mode: :independent]}

  The current site's entry wins, then `translatable`, then the options the
  Blueprint declared. Checked at boot by
  `Brando.Trait.Translatable.check_runtime_config!/0`.

  This lives outside `Brando.Trait.Translatable` on purpose. Every translatable
  Blueprint compiles against the trait, and asking which site is current goes
  through `Brando.Tenant`, which reaches the whole application, the Blueprints
  included. In the trait that is a compile-connected cycle; here it is a call a
  Blueprint makes at runtime.
  """
  alias Brando.Trait.Translatable

  @doc "The config of `module` for the current site; `compiled` when the application sets none."
  @spec get(module(), map()) :: map()
  def get(module, compiled) do
    case runtime_opts(module, Brando.Tenant.current_site_key()) do
      nil -> compiled
      opts -> cached_config(module, opts)
    end
  end

  defp runtime_opts(module, site_key) do
    env = Application.get_env(:brando, module, [])
    sites = Keyword.get(env, :translatable_sites, %{})

    cond do
      site_key && Map.has_key?(sites, site_key) -> Map.fetch!(sites, site_key)
      Keyword.has_key?(env, :translatable) -> Keyword.fetch!(env, :translatable)
      true -> nil
    end
  end

  # Called for every entry in a listing: parse each distinct config once.
  defp cached_config(module, opts) do
    key = {Translatable, module, :erlang.phash2(opts)}

    case :persistent_term.get(key, nil) do
      nil ->
        config = Translatable.config(opts)
        :persistent_term.put(key, config)
        config

      config ->
        config
    end
  end
end
