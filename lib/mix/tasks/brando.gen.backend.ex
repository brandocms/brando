if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.Backend do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task
    @shortdoc "Generates Brando backend assets with a reviewable diff"
    @moduledoc """
    Generates Vite backend assets without overwriting customized files.
    Existing package dependencies and scripts are preserved. This task does
    not install JavaScript packages or run a build.

        mix brando.gen.backend --upgrade

    brings an existing `assets/backend` up to the current template instead:
    package versions, `engines` and `packageManager`, `vite.config.js`, the
    retired `svelte.config.cjs`, yarn/npm lockfiles (the template uses pnpm),
    and the Dockerfile's `assets_backend` stage. Customized CSS and other
    existing files are kept. Install and build afterwards with
    `mix brando.assets.setup --backend-only`.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        group: :brando,
        schema: Mix.Brando.Igniter.Project.options() ++ [upgrade: :boolean]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      with {:ok, igniter, options} <-
             Mix.Brando.Igniter.Install.Configuration.namespace_options(igniter, igniter.args.options),
           {:ok, igniter, project} <- Mix.Brando.Igniter.Project.discover(igniter, options) do
        if igniter.args.options[:upgrade],
          do: Mix.Brando.Igniter.Assets.upgrade(igniter, project),
          else: Mix.Brando.Igniter.Assets.plan(igniter, project, [:backend])
      else
        {:error, %Igniter{} = igniter} -> igniter
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end
  end
else
  defmodule Mix.Tasks.Brando.Gen.Backend do
    use Mix.Task

    @doc "Requests recompilation when optional Igniter support becomes available."
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
    @shortdoc "Generates Brando backend assets (requires igniter)"
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.gen.backend")
  end
end
