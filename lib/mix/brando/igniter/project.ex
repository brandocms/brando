if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Project do
    @doc false
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Igniter.Code.Keyword, as: CodeKeyword
    alias Igniter.Code.Module, as: CodeModule
    alias Igniter.Libs.Ecto, as: EctoLibs
    alias Igniter.Libs.Phoenix
    alias Igniter.Project.Application, as: ProjectApplication
    alias Igniter.Project.Module, as: ProjectModule
    alias Sourceror.Zipper

    @module_options [:module, :web_module, :admin_module, :repo, :router, :endpoint]
    @module_name ~r/^(?:Elixir\.)?[A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*$/

    @doc "Options shared by source installers that need to select a Phoenix application."
    def options, do: Enum.map(@module_options, &{&1, :string})

    @doc """
    Discovers a standalone Phoenix application from the pending source tree.

    Does not compile the consumer, evaluate its configuration, prompt, or write
    files. Ambiguous selections are issues with explicit CLI alternatives.
    Namespace overrides are supplied by the composing task; runtime Brando
    configuration is deliberately not used to infer the consumer's identity.
    """
    def discover(igniter, options \\ []) do
      with {:ok, options} <- parse_modules(options),
           {:ok, igniter, mix} <- mix_source(igniter),
           :ok <- standalone_project(mix),
           {:ok, otp_app, app_module} <- identity(igniter, options),
           {:ok, application_module} <- application_module(mix),
           {:ok, igniter} <- require_application(igniter, application_module),
           {igniter, repos} <- EctoLibs.list_repos(igniter),
           {:ok, repo} <- select(igniter, repos, options, :repo),
           :ok <- postgres_repo(igniter, repo),
           {igniter, routers} <- Phoenix.list_routers(igniter),
           {:ok, router} <- select(igniter, routers, options, :router),
           {igniter, endpoints} <- Phoenix.endpoints_for_router(igniter, router),
           {:ok, endpoint} <- select(igniter, endpoints, options, :endpoint),
           {igniter, web_module} <- Phoenix.web_module_for_router(igniter, router) do
        {:ok, igniter,
         %{
           otp_app: otp_app,
           app_module: app_module,
           application_module: application_module,
           web_module: options[:web_module] || web_module,
           admin_module: options[:admin_module] || Module.concat(["#{inspect(app_module)}Admin"]),
           repo: repo,
           router: router,
           endpoint: endpoint
         }}
      else
        {:error, %Igniter{} = igniter} -> {:error, igniter}
        {:error, message} -> {:error, Igniter.add_issue(igniter, message)}
      end
    end

    defp identity(igniter, options) do
      case ProjectApplication.app_name(igniter) do
        app when app in [nil, true, false] ->
          {:error, "Expected a valid OTP application name in mix.exs project/0."}

        app ->
          {:ok, app, options[:module] || ProjectModule.module_name_prefix(igniter)}
      end
    rescue
      error in [RuntimeError, ArgumentError] ->
        {:error, "Could not discover the application identity from mix.exs: #{Exception.message(error)}"}
    end

    defp require_application(igniter, module) do
      case ProjectModule.find_module(igniter, module) do
        {:ok, {igniter, _source, _zipper}} ->
          {:ok, igniter}

        {:error, _igniter} ->
          {:error, "The configured application module #{inspect(module)} could not be found in source."}
      end
    end

    defp parse_modules(options) do
      Enum.reduce_while(@module_options, {:ok, options}, &parse_module_option/2)
    end

    defp parse_module_option(key, {:ok, options}) do
      case Keyword.fetch(options, key) do
        :error ->
          {:cont, {:ok, options}}

        {:ok, value} when is_binary(value) ->
          if Regex.match?(@module_name, value) do
            {:cont, {:ok, Keyword.put(options, key, Module.concat([value]))}}
          else
            {:halt, {:error, "#{flag(key)} must be an Elixir module name, got: #{inspect(value)}"}}
          end

        {:ok, value} ->
          {:halt, {:error, "#{flag(key)} must be an Elixir module name, got: #{inspect(value)}"}}
      end
    end

    defp mix_source(igniter) do
      igniter = Igniter.include_existing_file(igniter, "mix.exs", required?: true)

      case Rewrite.source(igniter.rewrite, "mix.exs") do
        {:ok, source} -> {:ok, igniter, source |> Rewrite.Source.get(:quoted) |> Zipper.zip()}
        {:error, _} -> {:error, igniter}
      end
    end

    defp standalone_project(mix) do
      with {:ok, project} <- CodeFunction.move_to_def(mix, :project, 0, target: :at),
           {:ok, body} <- Common.move_to_do_block(project),
           body <- Common.rightmost(body),
           true <- Igniter.Code.List.list?(body) do
        cond do
          CodeKeyword.keyword_has_path?(body, [:apps_path]) ->
            {:error, "Brando's Igniter installer currently supports standalone Phoenix projects, not umbrella roots."}

          not CodeKeyword.keyword_has_path?(body, [:app]) ->
            {:error, "Expected an :app entry in mix.exs project/0."}

          true ->
            :ok
        end
      else
        _ -> {:error, "Expected mix.exs project/0 to return a keyword list describing a standalone Phoenix project."}
      end
    end

    defp application_module(mix) do
      with {:ok, function} <- CodeFunction.move_to_def(mix, :application, 0, target: :at),
           {:ok, body} <- Common.move_to_do_block(function),
           {:ok, value} <- body |> Common.rightmost() |> CodeKeyword.get_key(:mod),
           {:ok, {module, _args}} when is_atom(module) and not is_nil(module) <- Common.expand_literal(value) do
        {:ok, module}
      else
        _ -> {:error, "Expected a literal mod: {MyApp.Application, []} in mix.exs application/0; no code was evaluated."}
      end
    end

    defp select(igniter, candidates, options, key) do
      candidates = candidates |> source_modules(igniter) |> Enum.sort()

      case {Keyword.fetch(options, key), candidates} do
        {:error, [module]} ->
          {:ok, module}

        {{:ok, module}, candidates} ->
          if module in candidates do
            {:ok, module}
          else
            {:error, "#{flag(key)} #{inspect(module)} is not an available #{key}. #{choices(key, candidates)}"}
          end

        {:error, []} ->
          {:error, "No #{key} could be found in the application source. #{missing_hint(key)}"}

        {:error, candidates} ->
          {:error, "Multiple #{key} modules were found. #{choices(key, candidates)}"}
      end
    end

    # Igniter also scans test files. A test-only Repo/router is not an install target.
    defp source_modules(modules, igniter) do
      folders = Igniter.Project.IgniterConfig.get(igniter, :source_folders)

      Enum.filter(modules, fn module ->
        {:ok, {_igniter, source, _zipper}} = ProjectModule.find_module(igniter, module)

        not String.starts_with?(source.path, "test/") and
          Enum.any?(folders, &String.starts_with?(source.path, String.trim_trailing(&1, "/") <> "/"))
      end)
    end

    defp postgres_repo(igniter, repo) do
      {:ok, {_igniter, _source, zipper}} = ProjectModule.find_module(igniter, repo)

      with {:ok, body} <- Common.move_to_do_block(zipper),
           {:ok, use_call} <- CodeModule.move_to_use(body, Ecto.Repo),
           {:ok, options} <- CodeFunction.move_to_nth_argument(use_call, 1),
           {:ok, adapter} <- CodeKeyword.get_key(options, :adapter),
           true <- Common.nodes_equal?(adapter, Ecto.Adapters.Postgres) do
        :ok
      else
        _ -> {:error, "#{inspect(repo)} must declare use Ecto.Repo with adapter: Ecto.Adapters.Postgres."}
      end
    end

    defp choices(_key, []), do: "No matching modules were found."

    defp choices(key, candidates) do
      "Choose explicitly: " <> Enum.map_join(candidates, " or ", &"#{flag(key)} #{inspect(&1)}")
    end

    defp missing_hint(:endpoint), do: "The selected router must be plugged into a Phoenix endpoint."
    defp missing_hint(:repo), do: "Brando requires an Ecto Repo backed by PostgreSQL."
    defp missing_hint(:router), do: "Brando requires a Phoenix router."
    defp flag(key), do: "--" <> String.replace(Atom.to_string(key), "_", "-")
  end
else
  defmodule Mix.Brando.Igniter.Project do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
