defmodule Mix.Tasks.Brando.Check.LegacyConversion do
  use Mix.Task

  alias Brando.Migration.LegacyConversion

  @shortdoc "Checks that the Villain → blocks upgrade kept every block, var, ref and fragment"

  @moduledoc """
  Compares the Villain JSON an upgraded site still has with the blocks the
  upgrade migrations (brando_103 to brando_133) made of it:

      mix brando.check.legacy_conversion
      mix brando.check.legacy_conversion --strict

  The upgrade guide has sites keep their Villain columns (`data`, `html`,
  `*_data`) until the converted content is verified; this task reads them. It
  finds them as brando_103 and brando_108 do, through `information_schema`: a
  json column named `data` or `<field>_data` next to its join table,
  `<table>_blocks` or `<table>_<field>`. A join table with no Villain column
  (dropped already, or a blocks field added since) is named in a note and not
  checked. It changes nothing.
  When tenancy is enabled, it checks every environment of every active site.

  ## What is compared

  Each entry's Villain list against the blocks the migrations wrote for it,
  level by level (root blocks, a container's blocks, a multi module's
  entries), pairing blocks by their place in the list:

    * the number of blocks at each level, by type;
    * per block (module, multi module, entry, container), its vars: one for
      each Villain var key, and a value wherever Villain had one (a string,
      `true`, an image or file id);
    * its refs: one for each Villain ref name;
    * its media refs: a picture ref whose Villain data had a `path` is
      linked to an image, a gallery ref has as many images in its gallery as
      its Villain data listed, and a video ref whose Villain data had a URL or
      remote id is linked to a video. A ref that showed nothing on 0.53 has
      nothing to lose;
    * its table rows: as many as its Villain table and list refs had rows;
    * its datasource: as many selected entries as Villain had;
    * a fragment block's `fragment_id`.

  A finding reads as a path to what is missing, grouped by table and entry:

      pages #12 › block 3 (module "Values") › vars: heading missing
      pages #2 › block 3 (module "Jobb med oss") › ref pic: legacy image images/site/posts/1n60vo3o9p06.jpg has no image now (lost in the conversion, or removed by an editor since)

  The check compares with Villain only, so media an editor removed since
  the conversion reads the same as media the conversion lost.

  `mix brando.repair.legacy_media` puts back the pictures, gallery images and
  videos it names, from the Villain data.

  ## What is not compared

  What the migrations change on purpose, and what an editor or a module save
  may have changed since:

    * Free-standing Villain blocks (text, picture, header, …) become a
      "Legacy Content Wrapper" module block holding their content in a ref
      named `content`; that block and ref are what is checked.
    * Table and list refs become table rows, so they are counted as rows,
      not refs. Refs without a name are dropped (brando_132).
    * Values are only checked for being there, not compared: markdown became
      HTML, media moved from ref data to image, video and gallery records
      (brando_133), video and picture settings were reshaped. Which image a
      picture ref links to is not compared with its Villain `path`.
    * Block uids (brando_123 replaces them), `hidden`/`collapsed`,
      descriptions, anchors and palettes.
    * Vars and refs a block has beyond Villain's: saving a module adds the
      vars and refs it defines to every block using it.
    * A single module's leftover `entries` (Villain rendered only a multi
      module's), and anything stored on the modules themselves. Module code
      that still reads an entry the Villain way (`link.data.vars.url`) is
      listed by `mix brando.doctor`, as it can be written again after the
      upgrade.
    * Page vars, globals and menu items (brando_109, 110, 116).
    * The rendered `html` columns. Diff the public pages for that.

  Run it right after the upgrade: blocks added, moved or removed in the
  editor since then show up as differences. Entries whose Villain column is
  empty were never converted and are skipped.

  Exits with status 1 when anything is missing. Blocks, table rows or
  datasource entries the converted content has beyond Villain's are listed
  too, and fail the run with `--strict`.
  """

  @switches [strict: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, _positional} = OptionParser.parse!(args, strict: @switches)
    Mix.Brando.start_quietly()

    results =
      Brando.Tenant.Job.each_active_environment(:all, fn ->
        LegacyConversion.check(Brando.Tenant.current_prefix() || "public")
      end)

    Enum.each(results, &report/1)

    if Enum.any?(results, &failed?(&1, opts[:strict] == true)), do: exit({:shutdown, 1})
  end

  defp failed?({:error, _message}, _strict?), do: true

  defp failed?({:ok, report}, strict?) do
    Enum.any?(report.findings, &(&1.severity == :missing or strict?))
  end

  defp report({:error, message}), do: Mix.shell().error(message)

  defp report({:ok, %{sources: [], dropped: []} = report}) do
    Mix.shell().info("No Villain columns in #{report.schema}: nothing to check.")
  end

  defp report({:ok, report}) do
    Mix.shell().info("Comparing Villain content with its blocks in #{report.schema}\n")

    report.findings
    |> Enum.chunk_by(& &1.table)
    |> Enum.each(fn findings ->
      Enum.each(findings, &print_finding/1)
      Mix.shell().info("")
    end)

    if report.dropped != [] do
      Mix.shell().info("Not checked, no Villain column:")

      for source <- report.dropped do
        Mix.shell().info("  #{source.join_table} (#{source.table}.#{source.column})")
      end

      Mix.shell().info("")
    end

    Mix.shell().info(summary(report))
  end

  defp print_finding(finding) do
    color = if finding.severity == :missing, do: :red, else: :yellow
    Mix.shell().info([color, "  " <> LegacyConversion.format(finding)])
  end

  defp summary(%{sources: []} = report), do: "No Villain column left to check in #{report.schema}."

  defp summary(report) do
    entries = report.sources |> Enum.map(& &1.entries) |> Enum.sum()
    columns = Enum.map_join(report.sources, ", ", &"#{&1.table}.#{&1.column}")
    {missing, extra} = Enum.split_with(report.findings, &(&1.severity == :missing))
    checked = "Checked #{entries} #{plural(entries, "entry", "entries")} (#{columns})"

    case {missing, extra} do
      {[], []} ->
        [:green, "#{checked}: every Villain block, var, ref and fragment came through."]

      {[], extra} ->
        [:yellow, "#{checked}: nothing missing, #{length(extra)} beyond Villain's (fails with --strict)."]

      {missing, extra} ->
        [:red, "#{checked}: #{length(missing)} missing, #{length(extra)} beyond Villain's."]
    end
  end

  defp plural(1, one, _many), do: one
  defp plural(_count, _one, many), do: many
end
