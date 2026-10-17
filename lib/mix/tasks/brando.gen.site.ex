if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.Site do
    use Igniter.Mix.Task
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @shortdoc "Plans optional CMS page rendering with explicit homepage ownership"
    @moduledoc """
    Adds CMS page controllers, templates, layouts and tenant context under Web.CMS.
    Run after `brando.install`, or compose with `brando.install --public-site`.

    It also adds the `/coming-soon` page `Brando.Plug.Lockdown` sends visitors to
    while `config :brando, lockdown: true`, with the plug in the CMS pipeline,
    and 404 and 500 pages in the site's layout, replacing phx.new's `ErrorHTML`
    while it is unchanged. Pages get a live preview target in Web.LivePreview,
    rendered with the CMS layout and templates, unless the module is customized.
    phx.new's `priv/static/robots.txt` is removed while it is unchanged, with
    `robots.txt` in `static_paths/0`, so `/robots.txt` is the SEO settings' text
    in development too.

        mix brando.gen.site --replace-phoenix-home
        mix brando.gen.site --interactive

    The replacement flag only removes the Phoenix PageController.home route at /.
    Existing Phoenix files are preserved. Custom homepages, catch-alls and owned
    file conflicts require explicit integration, including with `--yes`.
    Create and publish the index page separately in /admin/pages after setup.
    """

    @impl Igniter.Mix.Task
    def info(_, _) do
      %Igniter.Mix.Task.Info{
        group: :brando,
        schema: Mix.Brando.Igniter.Project.options() ++ [interactive: :boolean, replace_phoenix_home: :boolean]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      with {:ok, igniter, options} <-
             Mix.Brando.Igniter.Install.Configuration.namespace_options(igniter, igniter.args.options),
           {:ok, igniter, project} <- Mix.Brando.Igniter.Project.discover(igniter, options) do
        Mix.Brando.Igniter.Site.plan(igniter, project, options)
      else
        {:error, %Igniter{} = igniter} -> igniter
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end
  end
else
  defmodule Mix.Tasks.Brando.Gen.Site do
    use Mix.Task
    @doc "Requests recompilation when optional Igniter support becomes available."
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
    @shortdoc "Plans CMS pages (requires igniter)"
    @impl Mix.Task
    def run(_), do: Mix.Brando.missing_igniter!("brando.gen.site")
  end
end
