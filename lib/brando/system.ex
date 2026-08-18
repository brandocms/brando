# coveralls-ignore-start
defmodule Brando.System do
  @moduledoc """
  Simple checks on startup to verify system integrity
  """
  alias Brando.Cache
  alias Brando.Exception.ConfigError

  require Logger

  def initialize do
    run_checks()
    Brando.Tenant.Cache.warm()
    Brando.Assets.SiteAssets.warm()
    initialize_content_caches()
    :ok
  end

  defp initialize_content_caches do
    unless Brando.Tenant.enabled?() do
      Cache.Identity.set()
      Cache.SEO.set()
      Cache.Globals.set()
      Cache.Navigation.set()
      Cache.Palettes.set()
    end
  end

  def run_checks do
    Logger.info("==> Brando >> Running system checks...")
    Brando.Cache.put(:warnings, [], :infinite)
    {:ok, {:module_config, :exists}} = check_module_config_exists()
    {:ok, {:tenancy_config, :valid}} = check_tenancy_config()
    {:ok, {:villain_filters, :exists}} = check_villain_filters_exists()
    {:ok, {:media_path, :exists}} = check_media_path_exists()
    {:ok, {:media_url, :exists}} = check_media_url_exists()
    {:ok, {:executable, :exists}} = check_image_processing_executable()
    {:ok, {:identity, :exists}} = check_identity_exists()
    {:ok, {:seo, :exists}} = check_seo_exists()
    {:ok, {:authorization, :exists}} = check_authorization_exists()
    {:ok, {:env, :exists}} = check_env()
    {:ok, {:presence, :exists}} = check_presence_exists()

    Logger.info("==> Brando >> System checks complete!")
  end

  defp check_tenancy_config do
    :ok = Brando.Tenant.validate_config!()
    {:ok, {:tenancy_config, :valid}}
  end

  defp check_media_path_exists do
    path = Brando.config(:media_path) || raise_missing_media_path()

    case File.mkdir_p(path) do
      :ok -> {:ok, {:media_path, :exists}}
      {:error, _} -> raise_failed_media_path(path)
    end
  end

  defp raise_missing_media_path do
    raise ConfigError,
      message: """
      Missing :media_path configuration.

      Set

          config :brando, media_path: Path.expand("./media"),

      """
  end

  defp raise_failed_media_path(path) do
    raise ConfigError,
      message: """
      Failed creating :media_path

          #{inspect(path, pretty: true)}

      """
  end

  defp check_media_url_exists do
    case Brando.config(:media_url) do
      nil ->
        raise ConfigError,
          message: """
          Missing :media_url configuration.

          Set

              config :brando, media_url: "/media"

          """

      _path ->
        {:ok, {:media_url, :exists}}
    end
  end

  defp check_presence_exists do
    case Code.ensure_loaded(Brando.presence()) do
      {:module, _} ->
        if {:__brando_presence__, 0} in Brando.presence().__info__(:functions) do
          {:ok, {:presence, :exists}}
        else
          raise ConfigError,
            message: """
            Presence module missing __brando_presence__/0

            This means that it is not using `BrandoAdmin.Presence`.

            In your `#{inspect(Brando.presence())}` module:

              use BrandoAdmin.Presence,
                otp_app: #{inspect(Brando.otp_app())},
                pubsub_server: #{inspect(Brando.pubsub())},
                presence: __MODULE__
            """
        end

      {:error, _} ->
        raise ConfigError,
          message: """
          Presence module not found!
          """
    end
  end

  defp check_env do
    if Brando.env() == nil do
      raise ConfigError,
        message: """
        Environment is not set.

        Add to your `config/brando.exs`:

            import Config
            # ...
            config :brando, env: config_env()

        """
    end

    {:ok, {:env, :exists}}
  end

  defp check_image_processing_executable do
    case Brando.config(Brando.Images, :processor_module) do
      Brando.Images.Processor.Sharp ->
        raise ConfigError,
          message: """
          Brando.Images.Processor.Sharp has been removed.

          Image processing now uses Vix (libvips) instead of sharp-cli.

          Remove this line from your config:

              config :brando, Brando.Images, processor_module: Brando.Images.Processor.Sharp

          The default processor is now Brando.Images.Processor.Vix.
          """

      module ->
        module = module || Brando.Images.Processor.Vix
        apply(module, :confirm_executable_exists, [])
    end
  end

  defp check_identity_exists,
    do: check_content_exists(Brando.Sites.Identity, :identity, "identity", "identities")

  defp check_seo_exists,
    do: check_content_exists(Brando.Sites.SEO, :seo, "seo", "seo entries")

  # With tenancy enabled `public` holds only the structural template that new
  # environments are cloned from, so content lives in each site's live
  # environment and has to be checked there.
  defp check_content_exists(schema, key, singular, plural) do
    Enum.each(content_scopes(), &log_content(schema, singular, plural, &1))
    {:ok, {key, :exists}}
  end

  defp log_content(schema, singular, plural, {label, opts}) do
    case Brando.Repo.all(schema, opts) do
      [] -> Logger.error("==> No #{plural} found#{label}.")
      entries -> Enum.each(entries, &log_content_entry(&1, singular, label))
    end
  end

  defp log_content_entry(entry, singular, label) do
    Logger.debug("==> #{singular}: [#{entry.language}] exists#{label}")
  end

  defp content_scopes do
    if Brando.Tenant.enabled?(), do: live_environment_scopes(), else: [{"", []}]
  end

  defp live_environment_scopes do
    case Brando.Tenant.Registry.list_sites() do
      [] ->
        Logger.info("==> No sites provisioned yet; skipping content checks.")
        []

      sites ->
        Enum.flat_map(sites, &live_environment_scope/1)
    end
  rescue
    exception ->
      Logger.error("==> Could not read the site registry: #{Exception.message(exception)}")
      []
  end

  defp live_environment_scope(site) do
    case Enum.find(site.environments, & &1.live) do
      nil ->
        Logger.error("==> Site #{site.key} has no live environment.")
        []

      environment ->
        [{" for #{site.key}", [prefix: Brando.Tenant.prefix(site, environment)]}]
    end
  end

  defp check_authorization_exists do
    case Code.ensure_loaded(Brando.authorization()) do
      {:module, _} ->
        {:ok, {:authorization, :exists}}

      {:error, _} ->
        raise ConfigError,
          message: """


          Authorization module not found!

          Generate with:

              mix brando.gen.authorization

          """
    end
  end

  defp check_villain_filters_exists do
    case Code.ensure_loaded(Brando.filters()) do
      {:module, _} ->
        {:ok, {:villain_filters, :exists}}

      {:error, _} ->
        raise ConfigError,
          message: """


          Missing Villain filter module. Add:

          defmodule #{inspect(Brando.filters())} do
            use Brando.Villain.Filters
          end

          """
    end
  end

  defp check_module_config_exists do
    if Application.get_env(:brando, :repo_module) == nil do
      raise ConfigError,
        message: """


        Repo module not set in `config/brando.exs`. Add:

        config :brando, repo_module: MyApp.Repo
        """
    end

    if Application.get_env(:brando, :app_module) == nil do
      raise ConfigError,
        message: """


        Application module not set in `config/brando.exs`. Add:

        config :brando, app_module: MyApp
        """
    end

    if Application.get_env(:brando, :web_module) == nil do
      raise ConfigError,
        message: """


        Web module not set in `config/brando.exs`. Add:

        config :brando, app_module: MyApp
        """
    end

    if Application.get_env(:brando, :admin_module) == nil do
      raise ConfigError,
        message: """


        Admin module not set in `config/brando.exs`. Add:

        config :brando, admin_module: MyAppAdmin
        """
    end

    {:ok, {:module_config, :exists}}
  end
end

# coveralls-ignore-stop
