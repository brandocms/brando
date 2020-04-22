defmodule Brando.System do
  @moduledoc """
  Simple checks on startup to verify system integrity
  """
  require Logger

  def initialize do
    run_checks()
    set_cache()
  end

  def run_checks do
    Logger.info("==> Brando >> Running system checks...")
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
        {:error, {:identity, :failed}}

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
    if Brando.authorization() do
      {:ok, {:authorization, :exists}}
    else
      {:error,
       {:authorization,
        {"Authorization module not set in config. config :brando, authorization: MyApp.Authorization"}}}
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
