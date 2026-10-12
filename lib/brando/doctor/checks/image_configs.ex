defmodule Brando.Doctor.Checks.ImageConfigs do
  @moduledoc """
  Images made with older image settings: the configs whose sizes or formats
  changed after their images were processed. The same count as Utilities →
  Image sizes, which recreates them.

  Images made before Brando recorded settings are split into those whose
  files already match their config, which `mix brando.images.adopt` records,
  and those that differ, counted by how they differ: in formats or sizes (the
  config changed) or in their files (missing, other dimensions). Only a dry
  run: nothing is written. See `Brando.Images.Adoption`.

  When none of the images has a file in the media folder (see
  `Brando.Images.Adoption.media_status/0`), the check says so and asks for
  the media instead of recommending a recreate: only the records are
  compared then.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Context
  alias Brando.Images.Adoption
  alias Brando.Images.Processing

  @impl true
  def id, do: "image_configs"

  @impl true
  def label, do: dgettext("doctor", "Image configs")

  @impl true
  def run(%Context{} = context) do
    context
    |> Context.each_environment(&breakdown/0)
    |> evaluate()
  end

  # Above this many images without recorded settings in an environment, the
  # split compares records only and reads no files. Checking the files takes
  # about 0.4 ms an image (1,000 images with six sizes in two formats, warm
  # disk cache), so the system check stays within a couple of seconds.
  @file_check_limit 5_000

  defp breakdown do
    breakdown = Processing.config_breakdown()
    unrecorded = breakdown.unrecorded |> Map.values() |> Enum.sum()
    media = if breakdown.changed == %{} and unrecorded == 0, do: :ok, else: Adoption.media_status()
    # Without the files, only the records can be compared.
    check = if unrecorded > @file_check_limit or media != :ok, do: :records, else: :files

    {matching, differences} = if unrecorded == 0, do: {%{}, %{}}, else: dry_run(check)
    Map.merge(breakdown, %{matching: matching, differences: differences, check: check, media: media})
  end

  defp dry_run(check) do
    {:ok, differences} = Agent.start_link(fn -> %{} end)
    count = &Agent.update(differences, fn acc -> Map.update(acc, &1, 1, fn n -> n + 1 end) end)

    matching =
      [dry_run: true, check: check, on_differ: fn _image, verdict -> verdict |> Adoption.difference() |> count.() end]
      |> Adoption.by_target()
      |> Map.new(fn {target, counts} -> {target, counts.adopted} end)

    counted = Agent.get(differences, &Map.delete(&1, nil))
    Agent.stop(differences)
    {matching, counted}
  end

  @doc """
  Turns `[{environment_label, breakdown}]` into a result. A breakdown has
  `changed` and `unrecorded`, `%{config_target => image_count}` (images made
  with a config that changed since, and before configs were recorded), and `matching`,
  how many of each target's unrecorded images already match their config,
  checked by `check` (`:files` or `:records`) as
  `Brando.Images.Adoption.adopt_unrecorded/1` would with `dry_run: true`.
  It may have `differences`, `%{difference => image_count}` by
  `Brando.Images.Adoption.difference/1`, and `media`, what
  `Brando.Images.Adoption.media_status/0` said.

  Images made before Brando recorded image configs (`unrecorded`) are told
  apart from configs that really changed: after an upgrade from 0.54 every
  image is unrecorded, and reading that as "N configs changed" sends people
  to recreate a library for settings nobody touched. Most of them match, and
  `mix brando.images.adopt` records that without recreating them.
  """
  def evaluate(per_environment) do
    rows = fn key ->
      for {label, breakdown} <- per_environment,
          {target, count} <- Enum.sort(Map.get(breakdown, key, %{})),
          do: {label, target, count}
    end

    changed = rows.(:changed)
    unrecorded = rows.(:unrecorded)
    sum = fn rows -> rows |> Enum.map(&elem(&1, 2)) |> Enum.sum() end
    likely? = Enum.any?(per_environment, fn {_label, breakdown} -> breakdown[:check] == :records end)
    unrecorded_count = sum.(unrecorded)
    matching = min(sum.(rows.(:matching)), unrecorded_count)
    differ = unrecorded_count - matching

    unsynced =
      for {label, %{media: {:empty, root}}} <- per_environment do
        Context.label_item(label, dgettext("doctor", "no image files under %{path} (is the media synced?)", path: root))
      end

    differences =
      per_environment
      |> Enum.map(fn {_label, breakdown} -> Map.get(breakdown, :differences, %{}) end)
      |> Enum.reduce(%{}, &Map.merge(&1, &2, fn _kind, a, b -> a + b end))

    summaries =
      Enum.reject(
        [
          unsynced != [] && Enum.join(unsynced, "; "),
          changed != [] &&
            dngettext(
              "doctor",
              "%{count} config changed since its images were made",
              "%{count} configs changed since their images were made",
              length(changed)
            ) <> " (" <> dngettext("doctor", "%{count} image", "%{count} images", sum.(changed)) <> ")",
          unrecorded != [] &&
            dngettext(
              "doctor",
              "%{count} image was made before Brando recorded its settings",
              "%{count} images were made before Brando recorded their settings",
              unrecorded_count
            ) <> ": " <> unrecorded_split(unrecorded_count, matching, differ, likely?),
          differ > 0 && differences != %{} && differences(differences)
        ],
        &(&1 == false)
      )

    case summaries do
      [] ->
        ok(dgettext("doctor", "all images match their settings"))

      summaries ->
        warning(Enum.join(summaries, "; "),
          fix: if(unsynced == [], do: fix(changed, differ), else: unsynced_fix()),
          link: if(unsynced == [], do: {"#utils-image-sizes", dgettext("doctor", "Recreate changed images")}),
          items:
            Enum.map(changed, fn {label, target, count} ->
              Context.label_item(
                label,
                dngettext("doctor", "%{target}: %{count} image", "%{target}: %{count} images", count, target: target)
              )
            end) ++
              Enum.map(unrecorded, fn {label, target, count} ->
                Context.label_item(
                  label,
                  dngettext(
                    "doctor",
                    "%{target}: %{count} image without recorded settings",
                    "%{target}: %{count} images without recorded settings",
                    count,
                    target: target
                  )
                )
              end)
        )
    end
  end

  defp unsynced_fix,
    do:
      dgettext(
        "doctor",
        "sync the media to this machine (or mount its volume) and check again; until then every image counts as differing, and recreating needs the originals"
      )

  # Config differences call for recreating; missing files may be media not
  # synced here.
  @difference_order [:formats, :sizes, :missing_file, :dimensions, :error, :cdn]

  defp differences(counts) do
    parts =
      for kind <- @difference_order, count = counts[kind], count && count > 0 do
        difference(kind, count)
      end

    dgettext("doctor", "of those: %{differences}", differences: Enum.join(parts, ", "))
  end

  defp difference(:formats, count), do: dngettext("doctor", "%{count} in formats", "%{count} in formats", count)
  defp difference(:sizes, count), do: dngettext("doctor", "%{count} in sizes", "%{count} in sizes", count)

  defp difference(:missing_file, count),
    do: dngettext("doctor", "%{count} with a missing file", "%{count} with missing files", count)

  defp difference(:dimensions, count),
    do: dngettext("doctor", "%{count} in dimensions", "%{count} in dimensions", count)

  defp difference(:error, count), do: dngettext("doctor", "%{count} unreadable", "%{count} unreadable", count)

  defp difference(:cdn, count),
    do: dngettext("doctor", "%{count} on the CDN only", "%{count} on the CDN only", count)

  defp fix([], 0),
    do:
      dgettext(
        "doctor",
        "run mix brando.images.adopt, or Utilities → Recreate changed images, which records them without recreating them"
      )

  defp fix(_changed, 0), do: dgettext("doctor", "Utilities → Recreate changed images")

  defp fix(_changed, _differ),
    do:
      dgettext(
        "doctor",
        "Utilities → Recreate changed images recreates the images that differ; mix brando.images.adopt --dry-run --verbose lists why each one differs"
      )

  defp unrecorded_split(total, total, 0, false),
    do:
      dngettext(
        "doctor",
        "it already matches (mix brando.images.adopt records that)",
        "all already match (mix brando.images.adopt records that)",
        total
      )

  defp unrecorded_split(total, total, 0, true),
    do:
      dngettext(
        "doctor",
        "it likely matches (mix brando.images.adopt checks and records that)",
        "all likely match (mix brando.images.adopt checks and records that)",
        total
      )

  defp unrecorded_split(total, 0, total, _likely?),
    do:
      dngettext(
        "doctor",
        "it differs from its config (recreate it)",
        "all %{count} differ from their config (recreate them)",
        total
      )

  defp unrecorded_split(_total, matching, differ, likely?) do
    matches =
      if likely?,
        do:
          dngettext(
            "doctor",
            "%{count} likely matches (mix brando.images.adopt checks and records that)",
            "%{count} likely match (mix brando.images.adopt checks and records that)",
            matching
          ),
        else:
          dngettext(
            "doctor",
            "%{count} already matches (mix brando.images.adopt records that)",
            "%{count} already match (mix brando.images.adopt records that)",
            matching
          )

    matches <> ", " <> dngettext("doctor", "%{count} differs (recreate it)", "%{count} differ (recreate them)", differ)
  end
end
