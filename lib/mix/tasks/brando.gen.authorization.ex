if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.Authorization do
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
    @shortdoc "Plans an application authorization module (requires igniter)"
    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.gen.authorization")
  end
end
