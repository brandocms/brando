if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.Release do
    @doc false
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task

    @shortdoc "Plans release helpers and missing Mix release configuration"
    @moduledoc """
    #{@shortdoc}.

        mix brando.gen.release

    Creates ReleaseTasks and adds a release definition when absent. Existing release
    settings, secrets, runtime configuration and deployment files are preserved.
    Database migrations and deployment remain explicit operations.
    Namespace selection uses the shared --module/--web-module/--repo options.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{group: :brando, schema: Mix.Brando.Igniter.Project.options()}
    end

    @impl Igniter.Mix.Task
    def igniter(igniter), do: Mix.Brando.Igniter.Auxiliary.plan(igniter, :release)
  end
else
  defmodule Mix.Tasks.Brando.Gen.Release do
    use Mix.Task

    @doc false
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
    @shortdoc "Plans release helpers and missing Mix release configuration (requires igniter)"
    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.gen.release")
  end
end
