if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Install.Configuration do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Code.Keyword, as: CodeKeyword
    alias Igniter.Project.Config
    alias Sourceror.Zipper

    @namespaces [
      module: :app_module,
      web_module: :web_module,
      admin_module: :admin_module,
      repo: :repo_module,
      router: :router_module,
      endpoint: :endpoint_module
    ]

    def namespace_options(igniter, options) do
      Enum.reduce_while(@namespaces, {:ok, igniter, options}, &namespace_option/2)
    end

    defp namespace_option({option, key}, {:ok, igniter, options}) do
      case read(igniter, key) do
        {:ok, igniter, nil} ->
          {:cont, {:ok, igniter, options}}

        {:ok, igniter, value} when is_atom(value) ->
          if options[option] && options[option] != inspect(value) do
            {:halt,
             {:error,
              "--#{option} conflicts with configured :#{key} #{inspect(value)}. Update configuration explicitly before reinstalling."}}
          else
            {:cont, {:ok, igniter, Keyword.put_new(options, option, inspect(value))}}
          end

        {:ok, _igniter, value} ->
          {:halt, {:error, "Expected a module for :#{key}, got: #{inspect(value)}"}}

        {:error, message} ->
          {:halt, {:error, message}}
      end
    end

    def existing_tenancy(igniter) do
      with {:ok, igniter, mode} <- read(igniter, :tenancy_mode),
           {:ok, igniter, key} <- read(igniter, :site_key) do
        {:ok, igniter, if(mode, do: %{mode: mode, site_key: key})}
      end
    end

    # Read literal base configuration without evaluating the consumer's config.
    # Multiple conflicting declarations need review; guessing which conditional
    # or import order wins could silently switch an existing installation.
    def read(igniter, key) do
      {igniter, values} =
        Enum.reduce(["config/config.exs", "config/brando.exs"], {igniter, []}, &read_file(&1, &2, key))

      case Enum.uniq(values) do
        [] ->
          {:ok, igniter, nil}

        [{:ok, value}] ->
          {:ok, igniter, value}

        _ ->
          {:error,
           "Could not unambiguously read config :brando, :#{key}. Use one literal base configuration before installing."}
      end
    end

    defp read_file(path, {igniter, values}, key) do
      if Igniter.exists?(igniter, path) do
        igniter = Igniter.include_existing_file(igniter, path)
        quoted = igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:quoted)
        {_, found} = Macro.prewalk(quoted, [], &collect_value(&1, &2, key))
        {igniter, values ++ found}
      else
        {igniter, values}
      end
    end

    defp collect_value(node, found, key) do
      case config_value(Zipper.zip(node), key) do
        :missing -> {node, found}
        value -> {node, [value | found]}
      end
    end

    defp config_value(zipper, key) do
      cond do
        CodeFunction.function_call?(zipper, :config, 2) && CodeFunction.argument_equals?(zipper, 0, :brando) ->
          with {:ok, opts} <- CodeFunction.move_to_nth_argument(zipper, 1),
               {:ok, value} <- CodeKeyword.get_key(opts, key) do
            Common.expand_literal(value)
          else
            _ -> :missing
          end

        CodeFunction.function_call?(zipper, :config, 3) &&
          CodeFunction.argument_equals?(zipper, 0, :brando) && CodeFunction.argument_equals?(zipper, 1, key) ->
          {:ok, value} = CodeFunction.move_to_nth_argument(zipper, 2)
          Common.expand_literal(value)

        true ->
          :missing
      end
    end

    def configure(igniter, project, tenancy) do
      settings = [
        env: {:code, quote(do: config_env())},
        otp_app: project.otp_app,
        app_name: inspect(project.app_module),
        app_module: project.app_module,
        web_module: project.web_module,
        admin_module: project.admin_module,
        repo_module: project.repo,
        router_module: project.router,
        endpoint_module: project.endpoint,
        default_language: "en",
        languages: [[value: "en", text: "English"]],
        default_admin_language: "en",
        admin_languages: [[value: "en", text: "English"]],
        scope_default_language_routes: false,
        timezone: "Etc/UTC",
        lockdown: false,
        log_dir: {:code, quote(do: Path.expand("./log"))},
        media_path: {:code, quote(do: Path.expand("./media"))},
        media_url: "/media",
        preview_expiry_days: 2,
        use_default_errors: true
      ]

      igniter =
        Enum.reduce(settings, igniter, fn {key, value}, igniter ->
          if Config.configures_key?(igniter, "config.exs", :brando, [key]) do
            igniter
          else
            Config.configure_new(igniter, "brando.exs", :brando, [key], value)
          end
        end)

      igniter
      |> image_configuration()
      |> Config.configure_new("config.exs", project.otp_app, [:hmr], false)
      |> Config.configure_new("dev.exs", project.otp_app, [:hmr], true)
      |> vite_watchers(project)
      |> Config.configure_new(
        "brando.exs",
        :brando,
        [Brando.Villain, :parser],
        Module.concat(project.app_module, Villain.Parser)
      )
      |> configure_tenancy(tenancy.mode, tenancy.site_key)
      # Brando depends on Swoosh, which will not start without an API client;
      # Req is already one of Brando's dependencies.
      |> Mix.Brando.Igniter.SourceUpgrade.configure_swoosh_client()
      |> Mix.Brando.Igniter.SourceUpgrade.configure_brando_mailer(Module.concat(project.app_module, Mailer))
    end

    # The endpoint watchers in config/dev.exs that start the admin's and the
    # site's Vite dev servers with `mix phx.server`, for `hmr: true`.
    defp vite_watchers_code do
      """
      [
        # Vite dev servers for the admin and the site; Brando.Vite stops them with Phoenix.
        vite_admin: {Brando.Vite, :watch, [Path.expand("../assets/backend", __DIR__)]},
        vite_site: {Brando.Vite, :watch, [Path.expand("../assets/frontend", __DIR__)]}
      ]
      """
    end

    # Fills the endpoint's watchers in dev.exs when it has none (phx.new
    # --no-assets writes `watchers: []`) and dev.exs does not turn hmr off.
    # Watchers of the application's own are kept, with a notice unless they
    # already start both Vite projects.
    defp vite_watchers(igniter, project) do
      {igniter, dev} = dev_config(igniter)
      watchers = if dev, do: config_values(dev, project.otp_app, [project.endpoint, :watchers]), else: []
      hmr = if dev, do: config_values(dev, project.otp_app, [:hmr]), else: []

      cond do
        # The last value in the file is the one that counts
        match?([{:ok, false} | _], Enum.map(hmr, &Common.expand_literal/1)) ->
          igniter

        Enum.all?(watchers, &(Common.expand_literal(&1) == {:ok, []})) ->
          Config.configure(
            igniter,
            "dev.exs",
            project.otp_app,
            [project.endpoint, :watchers],
            {:code, Sourceror.parse_string!(vite_watchers_code())}
          )

        true ->
          source = Enum.map_join(watchers, "\n", &(&1 |> Zipper.node() |> Sourceror.to_string()))

          if String.contains?(source, "assets/backend") and String.contains?(source, "assets/frontend"),
            do: igniter,
            else: Igniter.add_notice(igniter, vite_watchers_notice(project))
      end
    end

    defp dev_config(igniter) do
      path = "config/dev.exs"

      if Igniter.exists?(igniter, path) do
        igniter = Igniter.include_existing_file(igniter, path)
        quoted = igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:quoted)
        {igniter, Zipper.zip(quoted)}
      else
        {igniter, nil}
      end
    end

    # The values `config` calls anywhere in the file give `path` under
    # `otp_app`, the last in the file first. Each call is matched in the whole file's zipper, so an alias
    # (`alias MyAppWeb.Endpoint`) resolves as it does for Config.configure.
    defp config_values(zipper, otp_app, path) do
      zipper
      |> Zipper.traverse([], fn zipper, found ->
        case config_value(zipper, otp_app, path) do
          {:ok, value} -> {zipper, [value | found]}
          :error -> {zipper, found}
        end
      end)
      |> elem(1)
    end

    defp config_value(zipper, otp_app, [key | rest] = path) do
      cond do
        CodeFunction.function_call?(zipper, :config, 3) and CodeFunction.argument_equals?(zipper, 0, otp_app) and
            CodeFunction.argument_equals?(zipper, 1, key) ->
          with {:ok, value} <- CodeFunction.move_to_nth_argument(zipper, 2), do: keyword_path(value, rest)

        CodeFunction.function_call?(zipper, :config, 2) and CodeFunction.argument_equals?(zipper, 0, otp_app) ->
          with {:ok, opts} <- CodeFunction.move_to_nth_argument(zipper, 1), do: keyword_path(opts, path)

        true ->
          :error
      end
    end

    defp keyword_path(zipper, []), do: {:ok, zipper}

    defp keyword_path(zipper, [key | rest]) do
      with {:ok, value} <- CodeKeyword.get_key(zipper, key), do: keyword_path(value, rest)
    end

    defp vite_watchers_notice(project) do
      """
      config/dev.exs already has watchers for #{inspect(project.endpoint)}, so they were kept. With
      hmr: true the admin and the site load their assets from Vite dev servers (ports 3333 and 3000),
      and mix phx.server does not start them. To start them, add the two entries of this list to
      the endpoint's watchers:

      #{vite_watchers_code() |> Code.format_string!() |> IO.iodata_to_binary()}
      """
    end

    def configure_tenancy(igniter, mode, key) do
      igniter
      |> tenancy_mode(mode)
      |> site_key(key)
      |> import_config()
    end

    defp tenancy_mode(igniter, mode) do
      file =
        if Config.configures_key?(igniter, "config.exs", :brando, [:tenancy_mode]), do: "config.exs", else: "brando.exs"

      Config.configure(igniter, file, :brando, [:tenancy_mode], mode)
    end

    defp image_configuration(igniter) do
      # Keep the installer image sizes/srcsets in one maintained template.
      template = Mix.Brando.Install.Templates.contents(:eex, "config/brando.exs")
      {:__block__, _, nodes} = Code.string_to_quoted!(template)

      {:config, _, [:brando, _, settings]} =
        Enum.find(nodes, fn
          {:config, _, [:brando, {:__aliases__, _, [:Brando, :Images]}, _]} -> true
          _ -> false
        end)

      Enum.reduce(settings, igniter, fn {key, value}, igniter ->
        Config.configure_new(igniter, "brando.exs", :brando, [Brando.Images, key], {:code, value})
      end)
    end

    defp site_key(igniter, nil) do
      Enum.reduce(["config/config.exs", "config/brando.exs"], igniter, &remove_site_key(&2, &1))
    end

    defp site_key(igniter, key) do
      file = if Config.configures_key?(igniter, "config.exs", :brando, [:site_key]), do: "config.exs", else: "brando.exs"
      Config.configure(igniter, file, :brando, [:site_key], key)
    end

    defp remove_site_key(igniter, file) do
      if Igniter.exists?(igniter, file), do: Igniter.update_elixir_file(igniter, file, &drop_site_key/1), else: igniter
    end

    defp drop_site_key(zipper) do
      zipper =
        Common.remove_all_matches(zipper, fn call ->
          CodeFunction.function_call?(call, :config, 3) && CodeFunction.argument_equals?(call, 0, :brando) &&
            CodeFunction.argument_equals?(call, 1, :site_key)
        end)

      Common.update_all_matches(zipper, &site_key_config?/1, fn call ->
        {:ok, opts} = CodeFunction.move_to_nth_argument(call, 1)
        CodeKeyword.remove_keyword_key(opts, :site_key)
      end)
    end

    defp site_key_config?(call) do
      CodeFunction.function_call?(call, :config, 2) && CodeFunction.argument_equals?(call, 0, :brando) &&
        case CodeFunction.move_to_nth_argument(call, 1) do
          {:ok, opts} -> CodeKeyword.keyword_has_path?(opts, [:site_key])
          :error -> false
        end
    end

    defp import_config(igniter) do
      igniter
      |> Igniter.include_or_create_file("config/config.exs", "import Config\n")
      |> Igniter.update_elixir_file("config/config.exs", fn zipper ->
        case CodeFunction.move_to_function_call(
               zipper,
               :import_config,
               1,
               &CodeFunction.argument_equals?(&1, 0, "brando.exs")
             ) do
          {:ok, _} ->
            {:ok, zipper}

          :error ->
            insert_config_import(zipper)
        end
      end)
    end

    defp insert_config_import(zipper) do
      case CodeFunction.move_to_function_call(zipper, :import_config, 1) do
        {:ok, anchor} -> {:ok, Common.add_code(anchor, ~s(import_config "brando.exs"), placement: :before)}
        :error -> {:ok, Common.add_code(zipper, ~s(import_config "brando.exs"))}
      end
    end
  end
else
  defmodule Mix.Brando.Igniter.Install.Configuration do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
