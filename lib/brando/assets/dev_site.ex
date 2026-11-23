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
  `Brando.Plug.SiteAssets` would serve while no shared preview pins the set
  (`Brando.Assets.SiteAssets.serve_path/3`). Every other site renders
  as in production, from its active set or the release's `priv/static`.
  The files of the dev site's project `public/` folder answer on its hosts
  and the admin's, as the dev server's pages name them host-relative
  (`public_file/2`).

  A shared preview of the dev site never loads from the dev server: it
  renders from the set it pins (`Brando.Assets.SiteAssets.Capture.ensure_set/2`),
  the environment's own set or the site's active set, else a capture of the
  release's `priv/static` when the site has no Vite project of its own
  (`own_project?/1`). With a project of its own and no set, sharing is
  refused with `{:error, :dev_site_without_set}`.

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
    site_key = key()
    if own_project?(site_key), do: Path.join("assets/sites", site_key), else: "assets/frontend"
  end

  @doc """
  Whether `site` (a site or its key) has a Vite project of its own in
  `assets/sites/<key>`, relative to the application. The release's
  `priv/static` holds `assets/frontend`'s build, not that project's.
  """
  @spec own_project?(Site.t() | String.t() | nil) :: boolean()
  def own_project?(%Site{key: site_key}), do: own_project?(site_key)
  def own_project?(site_key) when is_binary(site_key), do: File.dir?(Path.join("assets/sites", site_key))
  def own_project?(_none), do: false

  @doc """
  The file at `relative_path` in the `public/` folder of the dev site's
  Vite project (`assets/sites/<key>/public`), as an absolute path, or nil:
  when `site` is not the dev site while the setting applies, when the
  folder has no such file, and when the path leaves the folder, through
  `..`, as an absolute path or through a symlink.

  Vite serves these files on its own origin, but the dev site's pages name
  them host-relative: the layout's favicon, and the fonts in its CSS, which
  Vite injects into the page in development.
  """
  @spec public_file(Site.t() | String.t() | nil, String.t()) :: String.t() | nil
  def public_file(site, relative_path) when is_binary(relative_path) do
    with true <- dev_site?(site),
         public_dir = Path.expand(Path.join(["assets/sites", key(), "public"])),
         {:ok, safe_path} when safe_path != "" <- Path.safe_relative(relative_path, public_dir),
         file = Path.join(public_dir, safe_path),
         true <- File.regular?(file) do
      file
    else
      _miss -> nil
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
