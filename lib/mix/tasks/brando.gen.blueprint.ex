if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.Blueprint do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task

    @shortdoc "Generates a Blueprint through a reviewable Igniter plan"
    @moduledoc """
    Generates a content Blueprint with title/slug fields, an admin listing and form.

        mix brando.gen.blueprint Catalog Product
        mix brando.gen.blueprint People Person --plural people
        mix brando.gen.blueprint --interactive

    Accept and compile the Blueprint before running `mix brando.gen MyApp.Catalog.Product`.
    Public routing and authorization remain explicit application decisions.

    `--singular` and `--plural` override query names. The default plural appends `s`;
    use an override for irregular words. `--interactive` asks for missing arguments.
    The template precedence is `--template RELATIVE_PATH`, the consumer's
    `priv/templates/brando.gen.blueprint/blueprint.ex`, then Brando's default.
    Existing Blueprint files are preserved; different contents block generation.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        group: :brando,
        example: "mix brando.gen.blueprint Catalog Product",
        positional: [domain: [optional: true], schema: [optional: true]],
        schema:
          Mix.Brando.Igniter.Project.options() ++
            [interactive: :boolean, singular: :string, plural: :string, template: :string]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter), do: Mix.Brando.Igniter.Blueprint.plan(igniter)
  end
else
  defmodule Mix.Tasks.Brando.Gen.Blueprint do
    use Mix.Task

    @doc "Requests recompilation when optional Igniter support becomes available."
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
    @shortdoc "Generates a Blueprint (requires igniter)"
    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.gen.blueprint")
  end
end
