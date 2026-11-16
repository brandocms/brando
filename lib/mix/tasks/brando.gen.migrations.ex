if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Gen.Migrations do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task

    @shortdoc "Plans missing framework migration files"
    @moduledoc """
    Copies missing versioned Brando migrations and tenant migration templates through
    a reviewed Igniter plan. Historical files and timestamps are preserved.
    This does not recreate the pre-versioned baseline tables or run the database.

        mix brando.gen.migrations

    Apply public migrations with `mix brando.migrate` (`mix ecto.migrate` does the
    same), then named environments with `mix brando.migrate --tenants`. On a
    server, public migrations run before the new release starts: its code expects
    them, and with tenancy it reads the site registry at boot and stops until
    they have run. Run the new
    release's `bin/my_app eval "MyApp.ReleaseTasks.migrate()"` before starting
    it (the deployment guide has the steps). For initial installation use
    brando.install.

    In a script, pass `--yes`: with no input to read (a CI job, `ssh` without a
    terminal, stdin from `/dev/null`) the task otherwise stops when it asks for
    confirmation. `--yes` accepts the files without showing them.

    Existing copies are matched by name and left as they are, even when the
    template has changed since. `mix brando.migrations.check` lists the ones
    that have not run yet and differ from the current templates.

        mix brando.gen.migrations --refresh

    also rewrites every existing copy whose code differs from its current
    template (formatting and comments do not count), keeping its file name and
    timestamp, whether it has run or not. Rewriting a copy that has run changes
    nothing in a database that ran it; it matters where the migrations run
    again from scratch (a new test database, CI, a new server), which an old
    copy can stop with `relation "..." does not exist`. Review the diff: a copy
    may have been edited on purpose.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        group: :brando,
        schema: Mix.Brando.Igniter.Project.options() ++ [refresh: :boolean]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter), do: Mix.Brando.Igniter.Upgrade.migrations(igniter)
  end
else
  defmodule Mix.Tasks.Brando.Gen.Migrations do
    use Mix.Task

    @doc "Requests recompilation when optional Igniter support becomes available."
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
    @shortdoc "Plans missing framework migration files (requires igniter)"
    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.gen.migrations")
  end
end
