if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Site.Frontend do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Project.Config
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Igniter.Install.Configuration
    alias Mix.Brando.Igniter.Site.PageController
    alias Mix.Brando.Igniter.Template

    @module_name ~r/^[A-Z][A-Za-z0-9]*$/

    @doc """
    Plans one site's frontend (`mix brando.gen.site --site KEY`): a
    `Brando.Site.Frontend` module under `Web.Sites`, its layouts and its
    `PageHTML`, its `site_frontends` entry, and a page controller that renders
    it. `name` is the module's last segment, `nil` for the key camelized.
    """
    def plan(igniter, project, key, name) do
      with {:ok, igniter, mode} <- tenancy(igniter),
           {:ok, igniter} <- default_site(igniter, project),
           :ok <- valid_key(key),
           {:ok, name} <- module_name(key, name) do
        module = Module.concat([project.web_module, Sites, name])

        igniter
        |> files(project, key, module)
        |> register(key, module, mode)
        |> PageController.ensure_frontend(project)
        |> Igniter.add_notice("""
        #{inspect(module)} is the frontend of the site with key "#{key}", in its own layouts and page templates.
        No site record, content or frontend assets were created. The frontend takes effect
        with the next release: its modules are compiled into it.
        """)
      else
        {:error, %Igniter{} = igniter, message} -> Igniter.add_issue(igniter, message)
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end

    defp tenancy(igniter) do
      case Configuration.read(igniter, :tenancy_mode) do
        {:ok, igniter, mode} when mode in [nil, :none] ->
          {:error, igniter,
           "--site generates a site's frontend, and tenancy is off (tenancy_mode :none), so every request renders the default site. Set tenancy up first, for example with mix brando.setup.tenancy --mode multi."}

        {:ok, igniter, mode} ->
          {:ok, igniter, mode}

        {:error, message} ->
          {:error, igniter, message}
      end
    end

    defp default_site(igniter, project) do
      case ProjectModule.module_exists(igniter, PageController.module(project)) do
        {true, igniter} ->
          {:ok, igniter}

        {false, igniter} ->
          {:error, igniter,
           "There is no #{inspect(PageController.module(project))}, which renders every site's pages. Run mix brando.gen.site without --site first."}
      end
    end

    defp valid_key(key) do
      if Brando.Tenant.valid_key?(key),
        do: :ok,
        else:
          {:error,
           "--site #{inspect(key)} is not a site key: use lowercase letters, digits and single hyphens, such as acme-travel."}
    end

    defp module_name(key, nil) do
      name = key |> String.replace("-", "_") |> Macro.camelize()

      if Regex.match?(@module_name, name),
        do: {:ok, name},
        else:
          {:error,
           "--site #{key} gives no module name (#{name}). Name the module with --module, such as --module Site#{name}."}
    end

    defp module_name(_key, name) do
      if Regex.match?(@module_name, name),
        do: {:ok, name},
        else: {:error, "--module #{inspect(name)} is not a module name: use one segment such as AcmeTravel."}
    end

    defp files(igniter, project, key, module) do
      Enum.reduce(
        [
          {"site_frontend.ex", module},
          {"layouts.ex", Module.concat(module, Layouts)},
          {"html.ex", Module.concat(module, PageHTML)}
        ],
        igniter,
        fn {template, module}, igniter ->
          binding = [web_module: inspect(project.web_module), module: inspect(module), key: key]

          case Template.render(igniter, "brando.gen.site", template, binding) do
            {:ok, igniter, source} -> Files.create(igniter, "lib/#{Macro.underscore(module)}.ex", source)
            {:error, message} -> Igniter.add_issue(igniter, message)
          end
        end
      )
    end

    # In the file that configures :brando's tenancy: brando.exs, or config.exs
    # when the application keeps it there.
    defp register(igniter, key, module, mode) do
      case Configuration.read(igniter, :site_frontends) do
        {:ok, igniter, nil} ->
          igniter
          |> Config.configure(config_file(igniter), :brando, [:site_frontends], {:code, entry(key, module)})
          |> first_entry_notice(key, mode)

        {:ok, igniter, frontends} when is_map(frontends) ->
          case Map.fetch(frontends, key) do
            {:ok, ^module} ->
              igniter

            {:ok, other} ->
              Igniter.add_notice(igniter, """
              config :brando, site_frontends: already registers #{inspect(other)} for "#{key}", so it was left as it is.
              To render the site with #{inspect(module)}, register it there in place of #{inspect(other)}.
              """)

            :error ->
              igniter
              |> Config.configure(config_file(igniter), :brando, [:site_frontends], {:code, entry(key, module)},
                updater:
                  &Igniter.Code.Map.set_map_key(&1, key, Sourceror.parse_string!(inspect(module)), fn zipper ->
                    {:ok, zipper}
                  end)
              )
              |> then(&if(map_size(frontends) == 0, do: first_entry_notice(&1, key, mode), else: &1))
          end

        _ ->
          Igniter.add_notice(igniter, """
          config :brando, :site_frontends is not a map this task can read, so it was left as it is.
          Add the site's entry to it by hand: "#{key}" => #{inspect(module)}
          """)
      end
    end

    defp config_file(igniter) do
      cond do
        Config.configures_key?(igniter, "config.exs", :brando, [:site_frontends]) -> "config.exs"
        Config.configures_key?(igniter, "brando.exs", :brando, [:site_frontends]) -> "brando.exs"
        Config.configures_key?(igniter, "config.exs", :brando, [:tenancy_mode]) -> "config.exs"
        true -> "brando.exs"
      end
    end

    defp entry(key, module), do: Sourceror.parse_string!(~s(%{#{inspect(key)} => #{inspect(module)}}))

    # Outside :multi a site without an entry still renders the default site.
    defp first_entry_notice(igniter, key, :multi) do
      Igniter.add_notice(igniter, """
      "#{key}" is the first entry in config :brando, site_frontends, so every other site now
      answers 404 until it has an entry too: run mix brando.gen.site --site KEY for each of
      them, or register the module that should render it.
      """)
    end

    defp first_entry_notice(igniter, _key, _mode), do: igniter
  end
else
  defmodule Mix.Brando.Igniter.Site.Frontend do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
