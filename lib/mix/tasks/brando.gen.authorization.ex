if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.Authorization do
    @doc false
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task

    @shortdoc "Plans an application authorization module"
    @moduledoc """
    #{@shortdoc}.

        mix brando.gen.authorization

    Creates the default policy when absent. Customized policies are preserved and
    reported as conflicts; review permissions for application content types.
    Namespace selection uses the shared --module/--web-module/--repo options.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{group: :brando, schema: Mix.Brando.Igniter.Project.options()}
    end

    @impl Igniter.Mix.Task
    def igniter(igniter), do: Mix.Brando.Igniter.Auxiliary.plan(igniter, :authorization)
  end
else
  defmodule Mix.Tasks.Brando.Gen.Authorization do
    use Mix.Task

    @doc false
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
    @shortdoc "Plans an application authorization module (requires igniter)"
    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.gen.authorization")
  end
end
