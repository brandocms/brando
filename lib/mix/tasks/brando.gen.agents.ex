if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.Agents do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task

    @shortdoc "Plans Brando's files for coding agents"
    @moduledoc """
    #{@shortdoc}.

        mix brando.gen.agents
        mix brando.gen.agents --refresh

    Adds what `mix brando.install` gives coding agents and the application
    lacks: Brando's skills in `.claude/skills/`, the `brando` section and the
    site section in `AGENTS.md`, and a `CLAUDE.md` that imports `AGENTS.md`.
    Existing files are kept.

    `--refresh` replaces existing skill files with the versions this Brando
    ships; the diff shows what changes. `AGENTS.md` and `CLAUDE.md` are still
    kept, and skills the application added are left alone.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{group: :brando, schema: [refresh: :boolean], defaults: [refresh: false]}
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      Mix.Brando.Igniter.AgentFiles.plan(igniter, refresh: igniter.args.options[:refresh])
    end
  end
else
  defmodule Mix.Tasks.Brando.Gen.Agents do
    use Mix.Task

    @doc "Requests recompilation when optional Igniter support becomes available."
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
    @shortdoc "Plans Brando's files for coding agents (requires igniter)"
    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.gen.agents")
  end
end
