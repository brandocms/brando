if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Upgrade.Prepare do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task

    @shortdoc "Prepares a legacy consumer for library-owned Igniter upgrades"
    @moduledoc """
    Archives the recognized consumer-owned Mix.Tasks.Brando.Upgrade source outside
    compilation paths. Customized or unrecognized implementations block the plan.

        mix brando.upgrade.prepare
        mix compile

    Accept and compile in a separate invocation before using igniter.upgrade.
    The replacement migration-file command is mix brando.gen.migrations.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{group: :brando, schema: Mix.Brando.Igniter.Project.options()}
    end

    @impl Igniter.Mix.Task
    def igniter(igniter), do: Mix.Brando.Igniter.Upgrade.prepare(igniter)
  end
else
  defmodule Mix.Tasks.Brando.Upgrade.Prepare do
    use Mix.Task

    @doc "Requests recompilation when optional Igniter support becomes available."
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
    @shortdoc "Prepares a legacy consumer for library-owned Igniter upgrades (requires igniter)"
    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.upgrade.prepare")
  end
end
