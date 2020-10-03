# coveralls-ignore-start
defmodule Brando.System do
  @moduledoc """
  Simple checks on startup to verify system integrity
  """
  require Logger
  alias Brando.Exception.ConfigError
  alias Brando.Cache
  alias Brando.CDN
  alias Brando.Villain

  def initialize do
    run_checks()
    Cache.Identity.set()
    Cache.Globals.set()
    Cache.Navigation.set()
    :ok
  end

  def run_checks do
    Logger.info("==> Brando >> Running system checks...")

    {:ok, {:module_config, :exists}} = check_module_config_exists()
    {:ok, {:executable, :exists}} = check_image_processing_executable()
    {:ok, {:identity, :exists}} = check_identity_exists()
    {:ok, {:bucket, :exists}} = check_cdn_bucket_exists()
    {:ok, {:authorization, :exists}} = check_authorization_exists()
    {:ok, {:globals, _}} = check_valid_globals()
    {:ok, _} = check_invalid_wrapper_content()

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
    if CDN.enabled?() do
      CDN.ensure_bucket_exists()
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

    {:ok, {:module_config, :exists}}
  end

  defp check_valid_globals do
    search_terms = ["\\${GLOBAL:(\\w+)}", "\\${global:(\\w+)}"]

    invalid_ids =
      for {schema, fields} <- Villain.list_villains() do
        Enum.reduce(fields, [], fn {_, data_field, _html_field}, acc ->
          case Villain.search_villains_for_regex(schema, data_field, search_terms) do
            [] ->
              acc

            ids ->
              log_invalid_global(schema, ids)
              [ids | acc]
          end
        end)
      end

    # Return valid no matter what. We only want to warn
    {:ok, {:globals, invalid_ids}}
  end

  defp log_invalid_global(schema, ids) do
    require Logger

    Logger.error("""


      ==> Found deprecated global variable format `${global:key}`. Try `${global:system.key}` instead.
      ==> Schema.: #{inspect(schema)}
      ==> Ids....: #{inspect(ids)}
    """)
  end

  # wrapper should be moved from datasource block to template
  defp check_invalid_wrapper_content do
    {:ok, templates} = Brando.Villain.list_templates("all")

    if Enum.count(templates) > 0 do
      for t <- templates do
        if t.wrapper && String.contains?(t.wrapper, "${CONTENT}") do
          log_invalid_wrapper_content(t)
        end
      end
    end

    {:ok, {:wrappers, :ok}}
  end

  defp log_invalid_wrapper_content(t) do
    require Logger

    Logger.error("""


      ==> Found deprecated wrapper content format `${CONTENT}`. Use `${content}` instead.
      ==> Schema.: Template
      ==> Id.....: #{t.id} - #{t.name}
    """)
  end
end

# coveralls-ignore-stop
