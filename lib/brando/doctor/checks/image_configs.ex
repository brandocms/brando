defmodule Brando.Doctor.Checks.ImageConfigs do
  @moduledoc """
  Images made with older image settings: the configs whose sizes or formats
  changed after their images were processed. The same count as Utilities →
  Image sizes, which recreates them.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Context
  alias Brando.Images.Processing

  @impl true
  def id, do: "image_configs"

  @impl true
  def label, do: dgettext("doctor", "Image configs")

  @impl true
  def run(%Context{} = context) do
    context
    |> Context.each_environment(&Processing.config_breakdown/0)
    |> evaluate()
  end

  @doc """
  Turns `[{environment_label, %{changed: targets, unrecorded: targets}}]`,
  where targets are `%{config_target => image_count}`, into a result.

  Images made before Brando recorded image configs (`unrecorded`) are told
  apart from configs that really changed: after an upgrade from 0.54 every
  image is unrecorded, and reading that as "N configs changed" sends people
  to recreate a library for settings nobody touched. Recreating them is
  still the way to be sure, so both point at the same action.
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
              sum.(unrecorded)
            )
        ],
        &(&1 == false)
      )

    case summaries do
      [] ->
        ok(dgettext("doctor", "all images match their settings"))

      summaries ->
        warning(Enum.join(summaries, "; "),
          fix:
            if(changed == [],
              do: dgettext("doctor", "Utilities → Recreate changed images, once, to be sure they match"),
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
end
