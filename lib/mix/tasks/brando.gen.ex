if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task
    @shortdoc "Generates a resource from a compiled Blueprint through Igniter"
    @moduledoc """
    Generates context queries, admin views and routes for an accepted, compiled Blueprint.

        mix brando.gen MyApp.Catalog.Product
        mix brando.gen MyApp.Catalog.Product --public-route /products
        mix brando.gen --interactive

    Compile the Blueprint before calling this task. Pending Blueprint changes cannot
    be consumed in the same source plan. Existing context functions are preserved;
    conflicting generated files or routes block the plan, including with --yes.

    Public controllers and routes require --public-route. Review authorization and
    add a navigation entry explicitly. --main-field selects a persisted display and
    filter field; title, the first string field, or id is used by default.
    Consumer templates in priv/templates/brando.gen take precedence over defaults.
    """
    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        group: :brando,
        example: "mix brando.gen MyApp.Catalog.Product",
        positional: [blueprint: [optional: true]],
        schema:
          Mix.Brando.Igniter.Project.options() ++
            [interactive: :boolean, main_field: :string, public_route: :string]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter), do: Mix.Brando.Igniter.Resource.plan(igniter)
  end
else
  defmodule Mix.Tasks.Brando.Gen do
    use Mix.Task

    @doc "Requests recompilation when optional Igniter support becomes available."
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
    @shortdoc "Generates a resource (requires igniter)"
    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.gen")
  end
end
