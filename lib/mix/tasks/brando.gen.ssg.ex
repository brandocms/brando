if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.Ssg do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task

    @shortdoc "Plans the module listing the paths a static build stores"
    @moduledoc """
    #{@shortdoc}.

        mix brando.gen.ssg

    Generates `Web.SSG` in the discovered web namespace, which a static build
    (`Brando.SSG`, the Publishing screen's builds and `mix brando.ssg`) reads
    the paths to request and store from. It lists each site's published CMS
    pages that have a URL, in the site's languages; add a `urls` block for each
    other content type with pages. An existing module with other content
    blocks the plan. Namespace selection uses the shared
    --module/--web-module/--repo options.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{group: :brando, schema: Mix.Brando.Igniter.Project.options()}
    end

    @impl Igniter.Mix.Task
    def igniter(igniter), do: Mix.Brando.Igniter.Auxiliary.plan(igniter, :ssg)
  end
else
  defmodule Mix.Tasks.Brando.Gen.Ssg do
    use Mix.Task

    @doc "Requests recompilation when optional Igniter support becomes available."
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
    @shortdoc "Plans the module listing the paths a static build stores (requires igniter)"
    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.gen.ssg")
  end
end
