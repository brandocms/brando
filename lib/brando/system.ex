# coveralls-ignore-start
defmodule Brando.System do
  @moduledoc """
  Simple checks on startup to verify system integrity
  """
  require Logger
  alias Brando.Exception.ConfigError
  alias Brando.Cache
  alias Brando.System.Log
  alias Brando.Villain

  def initialize do
    run_checks()
    Cache.Identity.set()
    Cache.SEO.set()
    Cache.Globals.set()
    Cache.Navigation.set()
    Cache.Palettes.set()
    :ok
  end

  def run_checks do
    Logger.info("==> Brando >> Running system checks...")
    Brando.Cache.put(:warnings, [], :infinite)
    {:ok, {:module_config, :exists}} = check_module_config_exists()
    {:ok, {:villain_filters, :exists}} = check_villain_filters_exists()
    {:ok, {:media_path, :exists}} = check_media_path_exists()
    {:ok, {:media_url, :exists}} = check_media_url_exists()
    {:ok, {:executable, :exists}} = check_image_processing_executable()
    {:ok, {:identity, :exists}} = check_identity_exists()
    {:ok, {:seo, :exists}} = check_seo_exists()
    {:ok, {:authorization, :exists}} = check_authorization_exists()
    {:ok, {:block_syntax, _}} = check_block_syntax()
    {:ok, {:entry_syntax, _}} = check_entry_syntax()
    {:ok, {:env, :exists}} = check_env()
    {:ok, {:presence, :exists}} = check_presence_exists()

    Logger.info("==> Brando >> System checks complete!")
  end

  defp check_media_path_exists do
    case Brando.config(:media_path) do
      nil ->
        raise ConfigError,
          message: """
          Missing :media_path configuration.

          Set

              config :brando, media_path: Path.expand("./media"),

          """

      path ->
        if File.exists?(path) do
          {:ok, {:media_path, :exists}}
        else
          File.mkdir_p(path)

          if File.exists?(path) do
            {:ok, {:media_path, :exists}}
          else
            raise ConfigError,
              message: """
              Failed creating :media_path

                  #{inspect(path, pretty: true)}

              """
          end
        end
    end
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
    image_processing_module =
      Brando.config(Brando.Images, :processor_module) || Brando.Images.Processor.Sharp

    apply(image_processing_module, :confirm_executable_exists, [])
  end

  defp check_identity_exists do
    with [] <- Brando.repo().all(Brando.Sites.Identity) do
      Logger.error("==> No identities found.")
      {:ok, {:identity, :exists}}
    else
      identities ->
        for identity <- identities do
          Logger.debug("==> identity: [#{identity.language}] exists")
        end

        {:ok, {:identity, :exists}}
    end
  end

  defp check_seo_exists do
    with [] <- Brando.repo().all(Brando.Sites.SEO) do
      Logger.error("==> No seo entries found.")
      {:ok, {:seo, :exists}}
    else
      seos ->
        for seo <- seos do
          Logger.debug("==> seo: [#{seo.language}] exists")
        end

        {:ok, {:seo, :exists}}
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

  # check Villain modules for deprecated syntax.
  def check_block_syntax do
    search_terms = [vars: "\\${(.*?)}", for_loops: "{\\% (for .*? <- .*?) \\%}"]

    results = Villain.search_modules_for_regex(search_terms)

    for result <- results do
      log_invalid_block_syntax(:vars, result)
      log_invalid_block_syntax(:for_loops, result)
    end

    # Return valid no matter what. We only want to warn
    {:ok, {:block_syntax, nil}}
  end

  def check_entry_syntax do
    search_terms = [vars: "\\${(.*?)}", for_loops: "{\\% (for .*? <- .*?) \\%}"]

    for {schema, fields} <- Villain.list_villains() do
      for {_, data_field, _html_field} <- fields do
        case Villain.search_villains_for_regex(schema, data_field, search_terms, :with_data) do
          [] ->
            nil

          results ->
            meta = %{
              "namespace" => "#{inspect(schema)}#{inspect(data_field)}",
              "name" => "Entry"
            }

            for result <- results do
              log_invalid_block_syntax(:vars, Map.merge(result, meta))
              log_invalid_block_syntax(:for_loops, Map.merge(result, meta))
            end
        end
      end
    end

    {:ok, {:entry_syntax, nil}}
  end

  defp log_invalid_block_syntax(:vars, %{"vars" => nil}), do: nil

  defp log_invalid_block_syntax(:vars, %{
         "vars" => matches,
         "name" => name,
         "namespace" => namespace,
         "id" => id
       }) do
    for match <- matches do
      Log.warn("""
      Deprecated module syntax `${#{match}}`. Try `{{ #{String.replace(match, ":", ".")} }}` instead.

      Module..: #{inspect(name)}
      Namespace.: #{inspect(namespace)}
      Id........: #{inspect(id)}
      """)
    end
  end

  defp log_invalid_block_syntax(:for_loops, %{"for_loops" => nil}), do: nil

  defp log_invalid_block_syntax(:for_loops, %{
         "for_loops" => matches,
         "name" => name,
         "namespace" => namespace,
         "id" => id
       }) do
    for match <- matches do
      Log.warn("""
      Deprecated for loop syntax `{% #{match} %}`. Try `{% #{String.replace(match, "<-", "in")} %}` instead.

      Module..: #{inspect(name)}
      Namespace.: #{inspect(namespace)}
      Id........: #{inspect(id)}
      """)
    end
  end
end

# coveralls-ignore-stop
