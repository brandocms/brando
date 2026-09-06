if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.Frontend do
    use Igniter.Mix.Task
    @shortdoc "Generates Brando frontend assets with a reviewable diff"
    @moduledoc """
    Generates Vite frontend assets without overwriting customized files.
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
        Mix.Brando.Igniter.Assets.plan(igniter, project, [:frontend])
      else
        {:error, %Igniter{} = igniter} -> igniter
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end
  end
else
  defmodule Mix.Tasks.Brando.Gen.Frontend do
    use Mix.Task
    @shortdoc "Generates Brando frontend assets (requires igniter)"
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.gen.frontend")
  end
end
