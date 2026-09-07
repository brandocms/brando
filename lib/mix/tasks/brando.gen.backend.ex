if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.Backend do
    @doc false
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task
    @shortdoc "Generates Brando backend assets with a reviewable diff"
    @moduledoc """
    Generates Vite backend assets without overwriting customized files.
    Existing package dependencies and scripts are preserved. This task does
    not install JavaScript packages or run a build.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{group: :brando, schema: Mix.Brando.Igniter.Project.options()}
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      with {:ok, igniter, options} <-
             Mix.Brando.Igniter.Install.Configuration.namespace_options(igniter, igniter.args.options),
           {:ok, igniter, project} <- Mix.Brando.Igniter.Project.discover(igniter, options) do
        Mix.Brando.Igniter.Assets.plan(igniter, project, [:backend])
      else
        {:error, %Igniter{} = igniter} -> igniter
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end
  end
else
  defmodule Mix.Tasks.Brando.Gen.Backend do
    use Mix.Task

    @doc false
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
    @shortdoc "Generates Brando backend assets (requires igniter)"
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.gen.backend")
  end
end
