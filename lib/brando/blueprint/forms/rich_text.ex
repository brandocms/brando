defmodule Brando.Blueprint.Forms.RichText do
  @moduledoc """
  Optional rich-text authoring presets. Applying a preset adds its capabilities
  to an explicit extension list; it never replaces styles or content.
  """
  @external_resource Path.expand("../../../../assets/src/components/TipTap/capabilities.json", __DIR__)
  @registry @external_resource |> File.read!() |> Jason.decode!()

  def defaults, do: @registry["default"]
  def presets, do: @registry["presets"]
  def resolve(value) when value in [nil, "all"], do: defaults()
  def resolve(value) when is_binary(value), do: value |> String.split("|", trim: true) |> resolve()

  def resolve(value) when is_list(value) do
    value
    |> Enum.flat_map(fn
      key when key in [nil, "all"] -> defaults()
      "action_button" -> ["button"]
      key -> [key]
    end)
    |> Enum.uniq()
  end

  def add_preset(value, preset), do: Enum.uniq(resolve(value) ++ Map.get(presets(), to_string(preset), []))
end
