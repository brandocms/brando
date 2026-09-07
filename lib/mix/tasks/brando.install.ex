if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Install do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task

    @shortdoc "Installs Brando into a Phoenix application with a reviewable diff"
    @moduledoc """
    Installs Brando using Igniter. Also called by `mix igniter.install brando`.

        mix brando.install
        mix brando.install --interactive
        mix brando.install --tenancy-mode single --site-key my-site
        mix brando.install --public-site --replace-phoenix-home

    A new installation defaults to `--tenancy-mode none` without prompting.
    `--interactive` guides missing choices; explicit options take precedence.
    `--yes` accepts Igniter's diff; it does not select answers to guided questions.
    Existing tenancy settings are preserved on reruns.

    Phoenix source is extended in place. Existing application files, routes,
    tests, assets, dependencies and secrets are preserved. Conflicting scaffold
    files are reported for review, even with `--yes`. No database is touched.

    `--public-site` adds CMS page rendering in a separate Web.CMS namespace.
    An existing Phoenix homepage route needs explicit `--replace-phoenix-home`
    or an affirmative guided answer with `--public-site --interactive`.
    Existing controllers/templates/layouts are preserved; other homepage or
    catch-all ownership requires manual integration.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        group: :brando,
        example: "mix brando.install --interactive",
        schema:
          Mix.Brando.Igniter.Project.options() ++
            [
              interactive: :boolean,
              tenancy_mode: :string,
              site_key: :string,
              tenancy_prompt: :boolean,
              public_site: :boolean,
              replace_phoenix_home: :boolean
            ]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter), do: Mix.Brando.Igniter.Install.plan(igniter)

    # Retained for callers rendering maintained installer templates.
    defdelegate render(path), to: Mix.Brando.Install.Templates
    defdelegate parse_tenancy_options!(opts), to: Mix.Brando.Install.Options
    defdelegate resolve_tenancy_options!(opts, default), to: Mix.Brando.Install.Options
  end
else
  defmodule Mix.Tasks.Brando.Install do
    use Mix.Task

    @doc "Requests recompilation when optional Igniter support becomes available."
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
    @shortdoc "Installs Brando (requires igniter)"
    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.install")
  end
end
