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
    |> Context.each_environment(&Processing.changed_config_targets/0)
    |> evaluate()
  end

  @doc "Turns `[{environment_label, %{config_target => image_count}}]` into a result."
  def evaluate(per_environment) do
    changed = for {label, targets} <- per_environment, {target, count} <- Enum.sort(targets), do: {label, target, count}

    case changed do
      [] ->
        ok(dgettext("doctor", "all images match their settings"))

      changed ->
        configs = length(changed)
        images = changed |> Enum.map(&elem(&1, 2)) |> Enum.sum()

        warning(
          dngettext(
            "doctor",
            "%{count} config changed since its images were made",
            "%{count} configs changed since their images were made",
            configs
          ) <> " (" <> dngettext("doctor", "%{count} image", "%{count} images", images) <> ")",
          fix: dgettext("doctor", "Utilities → Recreate changed images"),
          link: {"#utils-image-sizes", dgettext("doctor", "Recreate changed images")},
          items:
            Enum.map(changed, fn {label, target, count} ->
              Context.label_item(
                label,
                dngettext("doctor", "%{target}: %{count} image", "%{target}: %{count} images", count, target: target)
              )
            end)
        )
    end
  end
end
