defmodule Mix.Tasks.Brando.Repair.LegacyMedia do
  use Mix.Task

  alias Brando.Migration.LegacyConversion
  alias Brando.Migration.LegacyMediaRepair

  @shortdoc "Puts back the pictures, gallery images and videos the Villain → blocks upgrade lost"

  @moduledoc """
  Puts back media that the Villain → blocks upgrade left out of converted
  refs, from the Villain columns (`data`, `*_data`) the site still has:

      mix brando.repair.legacy_media --dry-run
      mix brando.repair.legacy_media

  For sites that ran brando_133 before it made images of legacy media with no
  live `images` row. That version linked a picture ref to an image by `path`
  only, among images not in the trash, and left the others empty, though
  0.53 had shown them from the ref's own data; a gallery lost the images it
  found no row for. `mix brando.check.legacy_conversion` names each of them,
  `ref pic: legacy image … is not linked; the picture is empty`.

  For each, the task links the live image the legacy `sizes` or `path` name,
  or makes the row from the legacy data (path, sizes, dimensions, formats,
  dominant color, focal point), as brando_133 does now. A gallery gets its
  missing images at their legacy places, a video ref the video with its
  legacy URL. It pairs Villain blocks with converted ones as the check does,
  and skips, with the reason, a ref whose module block holds another module
  than Villain had there, and a gallery edited since the conversion.

    * `--dry-run` lists what it would do, and writes nothing.

  Run it with the Villain columns still there: they are the only copy of the
  data. A column already dropped is named, and its entries are not repaired.
  A second run finds nothing left to do. When tenancy is enabled, it repairs
  every environment of every active site.

  Afterwards, render the entries again with `mix brando.entries.resave`, and
  restart a running server, which caches what it rendered.
  """

  @switches [dry_run: :boolean]
  @aliases [n: :dry_run]

  @impl Mix.Task
  def run(args) do
    {opts, _positional} = Mix.Brando.parse_options!("brando.repair.legacy_media", args, @switches, aliases: @aliases)
    Mix.Brando.start_quietly()
    dry_run? = opts[:dry_run] == true

    results =
      Brando.Tenant.Job.each_active_environment(:all, fn ->
        LegacyMediaRepair.run(Brando.Tenant.current_prefix() || "public", dry_run: dry_run?)
      end)

    Enum.each(results, &report(&1, dry_run?))

    if Enum.any?(results, &match?({:error, _}, &1)), do: exit({:shutdown, 1})
  end

  defp report({:error, message}, _dry_run?), do: Mix.shell().error(message)

  defp report({:ok, %{sources: []} = result}, _dry_run?) do
    Mix.shell().info("""
    No Villain column left in #{result.schema}: there is no legacy data to repair from.\
    #{dropped(result.dropped)}\
    """)
  end

  defp report({:ok, %{repairs: []} = result}, _dry_run?) do
    Mix.shell().info("No media to repair in #{result.schema}.#{dropped(result.dropped)}")
  end

  defp report({:ok, result}, dry_run?) do
    heading = if dry_run?, do: " (dry run: nothing is written)", else: ""
    Mix.shell().info("Repairing legacy media in #{result.schema}#{heading}\n")

    for {finding, action} <- result.repairs do
      color = if match?({:skip, _}, action), do: :yellow, else: :default_color
      Mix.shell().info([color, "  #{LegacyConversion.format(%{finding | message: ref(finding)})} › ", describe(action)])
    end

    {skipped, repaired} = Enum.split_with(result.repairs, &match?({_, {:skip, _}}, &1))
    made = LegacyMediaRepair.made(repaired)

    Mix.shell().info("""

    #{summary(dry_run?, length(repaired), length(skipped), made)}#{dropped(result.dropped)}\
    """)

    cond do
      repaired == [] -> :ok
      dry_run? -> Mix.shell().info("Run without --dry-run to write them, then mix brando.entries.resave.")
      true -> Mix.shell().info("Run mix brando.entries.resave, and restart a running server.")
    end
  end

  # `ref pic: legacy image … is not linked; …` → `ref pic`
  defp ref(%{message: message}), do: message |> String.split(":", parts: 2) |> hd()

  defp describe(action), do: LegacyMediaRepair.describe(action)

  defp summary(dry_run?, repaired, skipped, made) do
    verb = if dry_run?, do: "to repair", else: "repaired"
    making = if dry_run?, do: "to make", else: "made"
    skipped = if skipped > 0, do: ", #{skipped} skipped", else: ""

    "#{count(repaired, "ref", "refs")} #{verb}#{skipped}: #{count(made.images, "image", "images")} and " <>
      "#{count(made.videos, "video", "videos")} #{making} from the legacy data."
  end

  defp dropped([]), do: ""

  defp dropped(dropped) do
    columns = Enum.map_join(dropped, ", ", &"#{&1.table}.#{&1.column}")
    "\nNot repaired, the Villain column is gone: #{columns}."
  end

  defp count(1, one, _many), do: "1 #{one}"
  defp count(n, _one, many), do: "#{n} #{many}"
end
