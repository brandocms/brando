defmodule Brando.System do
  @moduledoc """
  Simple checks on startup to verify system integrity
  """
  require Logger
  alias Brando.Exception.ConfigError

  def initialize do
    run_checks()
    set_cache()
  end

  def run_checks do
    Logger.info("==> Brando >> Running system checks...")
    {:ok, {:module_config, :exists}} = check_module_config_exists()
    {:ok, {:executable, :exists}} = check_image_processing_executable()
    {:ok, {:identity, :exists}} = check_identity_exists()
    {:ok, {:bucket, :exists}} = check_cdn_bucket_exists()
    {:ok, {:authorization, :exists}} = check_authorization_exists()
    {:ok, {:globals, :valid}} = check_valid_globals()
    Logger.info("==> Brando >> System checks complete!")
  end

  defp check_image_processing_executable do
    image_processing_module =
      Brando.config(Brando.Images)[:processor_module] || Brando.Images.Processor.Mogrify

    apply(image_processing_module, :confirm_executable_exists, [])
  end

  defp check_identity_exists do
    with [] <- Brando.repo().all(Brando.Sites.Identity),
         {:ok, _} <- Brando.Sites.create_default_identity() do
      {:ok, {:identity, :exists}}
    else
      {:error, _} ->
        raise ConfigError,
          message: """


          Failed creating default `identity` table.

          """

      _ ->
        {:ok, {:identity, :exists}}
    end
  end

  defp check_cdn_bucket_exists do
    if Brando.CDN.enabled?() do
      Brando.CDN.ensure_bucket_exists()
    else
      {:ok, {:bucket, :exists}}
    end
  end

  defp check_authorization_exists do
    if function_exported?(Brando.authorization(), :__info__, 1) do
      {:ok, {:authorization, :exists}}
    else
      raise ConfigError,
        message: """


        Authorization module not found!

        Generate with:

        mix brando.gen.authorization

        """
    end
  end

  defp check_module_config_exists do
    with {:app, m1} when is_atom(m1) <-
           {:app, Application.get_env(:brando, :app_module, "missing")},
         {:web, m2} when is_atom(m2) <-
           {:web, Application.get_env(:brando, :web_module, "missing")} do
      {:ok, {:module_config, :exists}}
    else
      {:app, "missing"} ->
        raise ConfigError,
          message: """


          Application module not set in `config/brando.exs`. Add:

          config :brando, app_module: MyApp
          """

      {:web, "missing"} ->
        raise ConfigError,
          message: """


          Web module not set in `config/brando.exs`. Add:

          config :brando, app_module: MyApp
          """
    end
  end

  defp check_valid_globals do
    search_terms = "\\$\\{GLOBAL\\:(\\w+)\\}"

    for {schema, fields} <- Brando.Villain.list_villains() do
      Enum.reduce(fields, [], fn {_, data_field, _html_field}, acc ->
        case Brando.Villain.search_villains_for_regex(schema, data_field, search_terms) do
          [] ->
            acc

          ids ->
            log_invalid_global(schema, ids)
            [ids | acc]
        end
      end)
    end

    # Return valid no matter what. We only want to warn
    {:ok, {:globals, :valid}}
  end

  defp log_invalid_global(schema, ids) do
    require Logger

    Logger.error("""
      ==> Found deprecated global variable format `${GLOBAL:key}`. Try `${GLOBAL:system.key}` instead.
      ==> Schema.: #{inspect(schema)}
      ==> Ids....: #{inspect(ids)}
    """)
  end

  defp set_cache do
    Brando.Sites.cache_identity()
  end
end
