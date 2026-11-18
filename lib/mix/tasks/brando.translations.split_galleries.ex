defmodule Mix.Tasks.Brando.Translations.SplitGalleries do
  @shortdoc "Give independent translations their own copies of shared galleries"

  @moduledoc """
  Gives every independent translation its own copy of each gallery record it
  still shares with another language version of its group, the ones
  `mix brando.doctor` lists under "Translation galleries".

      mix brando.translations.split_galleries
      mix brando.translations.split_galleries --yes

  A synchronized translation shows the source's galleries; **Make
  independent** copies them for it. A translation made independent before it
  did keeps the shared record, and an edit to its gallery changes the other
  version as well. The copies hold the same media in the same order, with
  each item's settings. Run it again at any time: a translation with its own
  galleries is left as it is. With tenancy on, it covers every environment of
  every active site.

  In a release: `bin/my_app rpc "Brando.Translations.SharedGalleries.repair()"`.

  It asks nothing, so `--yes` (or `--force`) is accepted and ignored. A
  translation that fails is listed, and the task then exits with status 1.
  """
  use Mix.Task

  @switches [yes: :boolean, force: :boolean]

  @spec run(any) :: no_return
  def run(args) do
    Mix.Brando.parse_options!("brando.translations.split_galleries", args, @switches, aliases: [y: :yes])

    Application.put_env(:logger, :level, :error)

    Mix.Tasks.Run.run([])

    case Brando.Translations.SharedGalleries.repair() do
      {:ok, 0} ->
        Mix.shell().info([:green, "\n==> No independent translation shares a gallery.\n"])

      {:ok, count} ->
        Mix.shell().info([:green, "\n==> Done: #{count} translation(s) have their own galleries now.\n"])

      {:error, failed} ->
        Mix.shell().error("\n==> Done, but #{failed} translation(s) failed. See above.\n")
        exit({:shutdown, 1})
    end
  end
end
