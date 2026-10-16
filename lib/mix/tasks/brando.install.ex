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
        mix brando.install --domain example.com --origin '//*.agency.example'

    A new installation defaults to `--tenancy-mode none` without prompting.
    `--interactive` guides missing choices; explicit options take precedence.
    `--yes` accepts Igniter's diff; it does not select answers to guided questions.
    Existing tenancy settings are preserved on reruns.

    Phoenix source is extended in place. Existing application files, routes,
    tests, assets, dependencies and secrets are preserved. Conflicting scaffold
    files are reported for review, even with `--yes`. No database is touched.
    `.formatter.exs` imports Brando's formatting of the Blueprint DSL, and a
    literal version in `mix.exs` moves to a `VERSION` file that `mix.exs`
    reads, where Florist looks for the release version.

    `--public-site` adds CMS page rendering in a separate Web.CMS namespace.
    An existing Phoenix homepage route needs explicit `--replace-phoenix-home`
    or an affirmative guided answer with `--public-site --interactive`.
    Existing controllers/templates/layouts are preserved; other homepage or
    catch-all ownership requires manual integration.

    Deployment hosts: `--domain` is the production domain, `--staging-domain`
    the staging host (default `staging.<domain>`), and `--origin` (repeatable)
    adds a trusted origin such as `//*.agency.example` or `https://host:8443`.
    With `--domain`, they fill the prod endpoint's `check_origin` in
    `config/prod.exs` (the domain, its subdomains, the staging host and each
    origin). They also set `PHX_HOST` in the new `.envrc.prod` and
    `.envrc.staging`, which are added to `.gitignore` and get their secrets
    after the changes are accepted, and `rel/env.sh.eex` makes the release
    source them on the server. Without `--domain` no `check_origin` is written
    and the hosts are `<app>.com` placeholders; `--interactive` asks for them
    instead. An existing `check_origin`, `.envrc.*` or `rel/env.sh.eex` is
    never replaced.

    For Florist's release build it also writes Brando's `Dockerfile` and
    `.dockerignore` when there are none, `ReleaseTasks` and a release with
    `steps: [:assemble, :tar]` when missing, relative `media_path` and
    `log_dir` in `config/prod.exs`, and the `.gitignore` lines Brando needs.
    An existing Dockerfile or release gets a notice of what Florist needs; an
    existing `.dockerignore` gets the exclusions it misses (with `!`
    exceptions, a notice instead).
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
              replace_phoenix_home: :boolean,
              domain: :string,
              staging_domain: :string,
              origin: :keep
            ]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter), do: Mix.Brando.Igniter.Install.plan(igniter)

    # Retained for callers rendering maintained installer templates.
    @doc "Renders a maintained installer template for existing generator callers."
    defdelegate render(path), to: Mix.Brando.Install.Templates

    @doc "Parses tenancy options for existing installer callers."
    defdelegate parse_tenancy_options!(opts), to: Mix.Brando.Install.Options

    @doc "Resolves tenancy options against a caller-supplied default."
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
