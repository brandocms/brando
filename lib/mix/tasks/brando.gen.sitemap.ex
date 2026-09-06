if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.Sitemap do
    use Igniter.Mix.Task

    @shortdoc "Plans a CMS sitemap module"
    @moduledoc """
    #{@shortdoc}.

        mix brando.gen.sitemap

    Generates a sitemap for published CMS pages using the discovered web namespace.
    Review its public URL rules before generating or publishing a sitemap.
    Namespace selection uses the shared --module/--web-module/--repo options.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{group: :brando, schema: Mix.Brando.Igniter.Project.options()}
    end

    @impl Igniter.Mix.Task
    def igniter(igniter), do: Mix.Brando.Igniter.Auxiliary.plan(igniter, :sitemap)
  end
else
  defmodule Mix.Tasks.Brando.Gen.Sitemap do
    use Mix.Task
    @shortdoc "Plans a CMS sitemap module (requires igniter)"
    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.gen.sitemap")
  end
end
