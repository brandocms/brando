if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Upgrade do
    @doc false
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task

    @shortdoc "Applies versioned Brando source upgrades through Igniter"
    @moduledoc """
    Called by mix igniter.upgrade brando with the old and new package versions.
    Only forward upgrades within the supported 0.54 development line and no
    newer than the loaded Brando dependency are accepted. Older applications
    must first follow guides/migrating_to_054.md; that source conversion precedes
    dependency compilation. Future version transitions require explicit recipes.

        mix brando.upgrade FROM TO

    To copy migration files without changing package versions, use
    mix brando.gen.migrations. Prepare consumer-owned legacy tasks first with
    mix brando.upgrade.prepare, then compile in a separate invocation.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        group: :brando,
        positional: [from: [optional: true], to: [optional: true]],
        schema: Mix.Brando.Igniter.Project.options()
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter), do: Mix.Brando.Igniter.Upgrade.plan(igniter)
  end
else
  defmodule Mix.Tasks.Brando.Upgrade do
    use Mix.Task

    @doc false
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
    @shortdoc "Applies versioned Brando source upgrades through Igniter (requires igniter)"
    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.upgrade")
  end
end
