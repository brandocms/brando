defmodule Brando.Assets.DevSite do
  @moduledoc """
  The site whose frontend the Vite dev server runs, on a multi-site
  installation in development.

      # config/dev.exs
      config :my_app, hmr: true, dev_site: "acme"

  With `tenancy_mode: :multi`, HMR on and `dev_site` naming a site, a request
  for any environment of that site loads its frontend from the Vite dev server
  and reads nothing from the site's active uploaded asset set or an
  environment's own set: not the Vite manifest, the critical CSS, nor a file
  `Brando.Plug.SiteAssets` would serve. Every other site renders
  as in production, from its active set or the release's `priv/static`.

  The setting is read only in development, outside static builds. Unset,
  every site loads from the dev server, as without it. Set in `:none` or
  `:single`, or naming no site, it is ignored, with one warning at boot
  (`warn_misconfigured/0`).
  """

  alias Brando.Sites.Site
  alias Brando.Tenant

  @doc """
  The key of the dev site while the setting applies, or nil: always nil
  outside development, in static builds, with `hmr: false`, and outside
  `:multi`, and nil when it names no site.
  """
  @spec key() :: String.t() | nil
  def key do
    with true <- Brando.env() == :dev,
         false <- Application.get_env(:brando, :ssg_run, false),
         :multi <- Tenant.mode(),
         true <- Application.get_env(Brando.otp_app(), :hmr) !== false,
         site_key when is_binary(site_key) <- configured(),
         %Site{} <- Tenant.Cache.get_site(site_key) do
      site_key
    else
      _ -> nil
    end
  end

  @doc "Whether `site` (a site or its key) is the dev site while the setting applies."
  @spec dev_site?(Site.t() | String.t() | nil) :: boolean()
  def dev_site?(%Site{key: site_key}), do: dev_site?(site_key)
  def dev_site?(site_key) when is_binary(site_key), do: key() == site_key
  def dev_site?(_none), do: false

  @doc """
  Whether the current process renders a site other than the dev site while
  the setting applies, so that its frontend comes from its build.
  """
  @spec other_site?() :: boolean()
  def other_site? do
    case key() do
      nil -> false
      site_key -> Tenant.current_site_key() != site_key
    end
  end

  @doc """
  The dev server's Vite project, relative to the application: the dev site's
  `assets/sites/<key>` when it exists, otherwise `assets/frontend`.
  """
  @spec frontend_dir() :: String.t()
  def frontend_dir do
    with site_key when is_binary(site_key) <- key(),
         dir = Path.join("assets/sites", site_key),
         true <- File.dir?(dir) do
      dir
    else
      _ -> "assets/frontend"
    end
  end

  @doc """
  Warns once when `dev_site` is set where it does nothing: outside `:multi`,
  or naming a site that does not exist. Development only, outside static
  builds, as `key/0`; reads the site
  cache, so call it after `Brando.Tenant.Cache.warm/0`.
  """
  @spec warn_misconfigured() :: :ok
  def warn_misconfigured do
    with :dev <- Brando.env(),
         false <- Application.get_env(:brando, :ssg_run, false),
         site_key when not is_nil(site_key) <- configured(),
         message when is_binary(message) <- misconfiguration(site_key) do
      Brando.System.Log.warn(message)
    end

    :ok
  end

  defp misconfiguration(site_key) do
    otp_app = Brando.otp_app()

    cond do
      Tenant.mode() != :multi ->
        "config :#{otp_app}, dev_site: #{inspect(site_key)} is ignored: it applies only with " <>
          "tenancy_mode: :multi (this installation runs #{inspect(Tenant.mode())})"

      not is_binary(site_key) or not match?(%Site{}, Tenant.Cache.get_site(site_key)) ->
        "config :#{otp_app}, dev_site: #{inspect(site_key)} is ignored: no site has that key. " <>
          "Every site loads its frontend from the Vite dev server."

      true ->
        nil
    end
  end

  defp configured, do: Application.get_env(Brando.otp_app(), :dev_site)
end
