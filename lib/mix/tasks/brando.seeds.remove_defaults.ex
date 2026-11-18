defmodule Mix.Tasks.Brando.Seeds.RemoveDefaults do
  use Mix.Task

  @shortdoc "List, then remove, the demo modules and content the seeds created"

  @moduledoc """
  List what still uses the seeds' demo modules (`brando-default-*`), and
  remove what nothing uses.

      mix brando.seeds.remove_defaults
      mix brando.seeds.remove_defaults --yes

  Without `--yes` it is a dry run: it lists each module of the seeds', and
  for each the pages, fragments and other entries whose blocks still use it,
  with their language and admin link, and changes nothing.

  With `--yes` it moves to the trash the homepage and footer fragment the
  seeds created, in each language, while they are exactly as seeded, and
  then the modules nothing uses any more. It never removes other content, or
  a module that is still used: those are listed, with what to change first.
  Edited content is always kept. `Brando.Setup.RemoveDefaults` says how
  "as seeded" is decided.

  Options:

    * `--yes` - remove, rather than list.
    * `--site <key>` - with tenancy, only this site's environments.
    * `--environment <key>` - with tenancy, only the environment with this
      key, in each site (or in `--site`'s).

  With tenancy it works in every environment of every site, each on its own.

  A server that is already running keeps what it cached before: restart it,
  or use Configuration → Cache → Empty all caches in its admin. In a release,
  where there is no Mix, run it on the running node, which updates its
  caches itself:

      bin/my_app rpc "Brando.Setup.Seeds.remove_defaults()"
      bin/my_app rpc "Brando.Setup.Seeds.remove_defaults(yes: true)"
  """

  @impl Mix.Task
  @spec run([binary]) :: :ok
  def run(args) do
    {opts, _rest} =
      Mix.Brando.parse_options!(
        "brando.seeds.remove_defaults",
        args,
        [yes: :boolean, site: :string, environment: :string],
        aliases: [y: :yes]
      )

    Application.put_env(:logger, :level, :error)
    Mix.Task.run("app.start")

    Mix.shell().info("""

    ---------------------------------
    % Brando Remove Seeded Defaults
    ---------------------------------
    """)

    remove_opts = [
      yes: Keyword.get(opts, :yes, false),
      site: opts[:site],
      environment: opts[:environment],
      info: fn line -> Mix.shell().info(line) end
    ]

    case Brando.Setup.Seeds.remove_defaults(remove_opts) do
      {:ok, reports} ->
        if opts[:yes] && Enum.any?(reports, &removed?/1) do
          Mix.shell().info(
            "\nA server that was already running keeps serving what it cached before. " <>
              "Restart it, or empty its caches in the admin under Configuration → Cache → Empty all caches."
          )
        end

        :ok

      {:error, message} ->
        if opts[:yes] && message =~ "Already moved to the trash" do
          Mix.shell().info("\nA server that was already running keeps serving what it cached before: restart it.")
        end

        Mix.raise("mix brando.seeds.remove_defaults: " <> message)
    end
  end

  defp removed?(report), do: Enum.any?(report.modules ++ report.entries, &(&1.status == :removed))
end
