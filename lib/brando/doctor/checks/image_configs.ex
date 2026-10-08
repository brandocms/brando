defmodule Brando.Doctor.Checks.ImageConfigs do
  @moduledoc """
  Images made with older image settings: the configs whose sizes or formats
  changed after their images were processed. The same count as Utilities →
  Image sizes, which recreates them.

  Images made before Brando recorded settings are split into those whose
  files already match their config, which `mix brando.images.adopt` records,
  and those that differ. Only a dry run: nothing is written. See
  `Brando.Images.Adoption`.
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
    check = if unrecorded > @file_check_limit, do: :records, else: :files

    matching =
      if unrecorded == 0,
        do: %{},
        else:
          [dry_run: true, check: check]
          |> Adoption.by_target()
          |> Map.new(fn {target, counts} -> {target, counts.adopted} end)

    Map.merge(breakdown, %{matching: matching, check: check})
  end

  @doc """
  Turns `[{environment_label, breakdown}]` into a result. A breakdown has
  `changed` and `unrecorded`, `%{config_target => image_count}` (images made
  with a config that changed since, and before configs were recorded), and `matching`,
  how many of each target's unrecorded images already match their config,
  checked by `check` (`:files` or `:records`) as
  `Brando.Images.Adoption.adopt_unrecorded/1` would with `dry_run: true`.

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

    summaries =
      Enum.reject(
        [
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
            ) <> ": " <> unrecorded_split(unrecorded_count, matching, differ, likely?)
        ],
        &(&1 == false)
      )

    case summaries do
      [] ->
        ok(dgettext("doctor", "all images match their settings"))

      summaries ->
        warning(Enum.join(summaries, "; "),
          fix:
            if(changed == [] and differ == 0,
              do:
                dgettext(
                  "doctor",
                  "run mix brando.images.adopt, or Utilities → Recreate changed images, which records them without recreating them"
                ),
              else: dgettext("doctor", "Utilities → Recreate changed images")
            ),
          link: {"#utils-image-sizes", dgettext("doctor", "Recreate changed images")},
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
    do: dngettext("doctor", "it differs (recreate it)", "none match (recreate them)", total)

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
