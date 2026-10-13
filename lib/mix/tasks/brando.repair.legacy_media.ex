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
      mix brando.repair.legacy_media --converted-at 2026-10-12T22:40:00

  For sites that ran brando_133 before it made images of legacy media with no
  live `images` row. That version linked a picture ref to an image by `path`
  only, among images not in the trash, and left the others empty, though
  0.53 had shown them from the ref's own data; a gallery lost the images it
  found no row for. `mix brando.check.legacy_conversion` names each of them,
  `ref pic: legacy image … has no image now (lost in the conversion, or
  removed by an editor since)`.

  For each, the task links the live image the legacy data names, or makes
  the row from it (path, sizes, dimensions, formats, dominant color, focal
  point), as brando_133 does now. A gallery gets its missing images at their
  legacy places, a video ref the video with its legacy URL.

  It writes only where it can tell the media was lost in the conversion,
  not removed by an editor since, and skips the rest with the reason (see
  `Brando.Migration.LegacyMediaRepair`): an entry whose blocks no longer
  line up with its Villain list, an entry edited since the conversion (its
  `edited_at`), a block or gallery changed since, an image to make while
  images were deleted for good since, or whenever it can't tell. Each ref is
  locked while it is written, and written only while still empty.

    * `--dry-run` lists what it would do, and writes nothing.
    * `--converted-at` (ISO 8601, UTC) is the time after which a change
      counts as an editor's. By default it is when brando_133 ran, or
      brando_175 (which starts recording edits) when that ran later, read
      from `schema_migrations` through their copies in the migrations
      directory.

  Run it with the Villain columns still there: they are the only copy of the
  data. A column already dropped is named, and its entries are not repaired.
  A second run finds nothing left to do. When tenancy is enabled, it repairs
  every environment of every active site.

  Afterwards, render the entries again with `mix brando.entries.resave`, and
  restart a running server, which caches what it rendered.
  """

  @switches [dry_run: :boolean, converted_at: :string]
  @aliases [n: :dry_run]

  @impl Mix.Task
  def run(args) do
    {opts, _positional} = Mix.Brando.parse_options!("brando.repair.legacy_media", args, @switches, aliases: @aliases)
    Mix.Brando.start_quietly()
    dry_run? = opts[:dry_run] == true
    repair_opts = [dry_run: dry_run?] ++ converted_at(opts[:converted_at])

    results =
      Brando.Tenant.Job.each_active_environment(:all, fn ->
        LegacyMediaRepair.run(Brando.Tenant.current_prefix() || "public", repair_opts)
      end)

    Enum.each(results, &report(&1, dry_run?))

    if Enum.any?(results, &match?({:error, _}, &1)), do: exit({:shutdown, 1})
  end

  defp converted_at(nil), do: []

  defp converted_at(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, time} -> [converted_at: time]
      {:error, _} -> Mix.raise("--converted-at takes an ISO 8601 time in UTC, as 2026-10-12T22:40:00")
    end
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

    if result.converted_at,
      do: Mix.shell().info("Changes after #{result.converted_at} UTC count as editors'.\n")

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

  # `ref pic: legacy image … has no image now (…)` → `ref pic`
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
