if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Install.Configuration do
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
      |> image_configuration(project, tenancy)
      |> Config.configure_new("config.exs", project.otp_app, [:hmr], false)
      |> Config.configure_new(
        "brando.exs",
        :brando,
        [Brando.Villain, :parser],
        Module.concat(project.app_module, Villain.Parser)
      )
      |> configure_tenancy(tenancy.mode, tenancy.site_key)
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

    defp image_configuration(igniter, project, tenancy) do
      # Keep the installer image sizes/srcsets in one maintained template.
      binding =
        Mix.Brando.Igniter.Install.template_binding(project) ++ [tenancy_mode: tenancy.mode, site_key: tenancy.site_key]

      template = Mix.Brando.Install.Templates.contents(:eex, "config/brando.exs")
      {:__block__, _, nodes} = template |> EEx.eval_string(binding) |> Code.string_to_quoted!()

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
end
