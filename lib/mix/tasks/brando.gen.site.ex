if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.Site do
    use Igniter.Mix.Task
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @shortdoc "Plans optional CMS page rendering with explicit homepage ownership"
    @moduledoc """
    Adds CMS page controllers, templates, layouts and tenant context under Web.CMS.
    A new `brando.install` composes it unless given `--no-public-site`; run it
    to add the site to an application installed without one.

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

    ## One site's frontend

    With tenancy on, `--site KEY` generates the layouts and page templates of
    the site with that key instead, as a `Brando.Site.Frontend` module under
    Web.Sites (`acme-travel` gives `Web.Sites.AcmeTravel`; `--module Name`
    names it), and registers it in `config :brando, site_frontends`. The page
    controller gets `Brando.Plug.SiteFrontend` while it is as generated.

        mix brando.gen.site --site acme-travel
        mix brando.gen.site --site 2025 --module Anniversary

    With `tenancy_mode :multi` it also creates the site's own Vite project in
    `assets/sites/KEY/`, from the templates that give a new installation
    `assets/frontend`, building into its `dist/` folder; an existing folder is
    left as it is. It installs and builds nothing, and creates no site record
    or content.
    """

    @impl Igniter.Mix.Task
    def info(_, _) do
      %Igniter.Mix.Task.Info{
        group: :brando,
        schema:
          Mix.Brando.Igniter.Project.options() ++
            [interactive: :boolean, replace_phoenix_home: :boolean, site: :string]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      # With --site, --module names the site's module, not the application's.
      {site_module, options} =
        if igniter.args.options[:site],
          do: Keyword.pop(igniter.args.options, :module),
          else: {nil, igniter.args.options}

      with {:ok, igniter, options} <- Mix.Brando.Igniter.Install.Configuration.namespace_options(igniter, options),
           {:ok, igniter, project} <- Mix.Brando.Igniter.Project.discover(igniter, options) do
        case options[:site] do
          nil -> Mix.Brando.Igniter.Site.plan(igniter, project, options)
          key -> Mix.Brando.Igniter.Site.Frontend.plan(igniter, project, key, site_module)
        end
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
