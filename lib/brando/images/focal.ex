defmodule Brando.Images.Focal do
  @moduledoc """
  An image's focal point, as `x` and `y` percentages of the upright image.

  The site shows it as CSS `object-position: x% y%`. How a cropping size is
  cut from the original around it depends on `mode`:

    * `:center` (the default, and what a focal point stored without a mode
      reads as): the cut is centred on the point, so the subject the point
      marks stays in the cut. An editor setting the point sets this mode.
    * `:position`: the cut lines up with the image the way `object-position`
      does, splitting the part cut off an axis `x : (100 - x)`. The Figma
      import sets this mode, with a point worked out so the site shows the
      Figma crop.
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Images",
    schema: "Focal",
    singular: "focal",
    plural: "focals",
    gettext_module: Brando.Gettext

  data_layer :embedded

  @primary_key false
  @allow_mark_as_deleted false

  attributes do
    attribute :x, :integer, required: true, default: 50
    attribute :y, :integer, required: true, default: 50
    attribute :mode, :enum, values: [:center, :position], default: :center
  end

  @derive {Jason.Encoder, only: [:x, :y, :mode]}

  @doc """
  The changeset an image casts its focal point with: a point moved without a
  mode in the params is set by hand, and reads as `:center` again.
  """
  def cast(focal, params) do
    changeset = changeset(focal, params)
    moved? = Map.has_key?(changeset.changes, :x) or Map.has_key?(changeset.changes, :y)

    if moved? and not mode_param?(params),
      do: Ecto.Changeset.put_change(changeset, :mode, :center),
      else: changeset
  end

  defp mode_param?(params) when is_map(params), do: Map.has_key?(params, :mode) or Map.has_key?(params, "mode")
  defp mode_param?(_params), do: false

  @doc """
  The mode of a focal point, stored or a plain map with atom or string keys
  and values. A missing or unknown mode reads as `:center`.
  """
  def mode(%{mode: mode}), do: to_mode(mode)
  def mode(%{"mode" => mode}), do: to_mode(mode)
  def mode(_focal), do: :center

  defp to_mode(mode) when mode in [:position, "position"], do: :position
  defp to_mode(_mode), do: :center
end
