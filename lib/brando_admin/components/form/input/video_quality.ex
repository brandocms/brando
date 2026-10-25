defmodule BrandoAdmin.Components.Form.Input.VideoQuality do
  @moduledoc """
  The quality select of a video's placements: the video drawer, a video
  block, and a gallery's video settings. It offers what
  `Brando.Videos.Playback.choices/1` gives for the video, under an empty
  option that inherits (`inherit`), and renders only a hidden input for a
  video without choices, so a stored value survives the form's submit.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias Brando.Videos.Playback
  alias BrandoAdmin.Components.Form.Primitives

  attr :field, Phoenix.HTML.FormField, required: true
  attr :video, :any, default: nil
  attr :choices, :list, default: nil, doc: "`Brando.Videos.Playback.choices/1`, when the video isn't at hand"
  attr :inherit, :string, required: true, doc: "the empty option's label"
  attr :instructions, :string, default: nil

  def select(assigns) do
    current = Playback.normalize(assigns.field.value)
    choices = assigns.choices || Playback.choices(assigns.video)

    # A stored quality the video no longer has stays selected rather than
    # being dropped on the next submit
    options = if current && current not in choices, do: choices ++ [current], else: choices

    assigns =
      assigns
      |> assign(:current, current)
      |> assign(:options, options)
      |> assign(:show?, choices != [])

    ~H"""
    <Primitives.field_base
      :if={@show?}
      field={@field}
      label={gettext("Quality")}
      instructions={@instructions}
      class="video-quality"
    >
      <select id={@field.id} name={@field.name} class="admin-select">
        <option value="" selected={is_nil(@current)}>{@inherit}</option>
        <option :for={quality <- @options} value={quality} selected={quality == @current}>
          {Playback.label(quality)}
        </option>
      </select>
    </Primitives.field_base>
    <input :if={!@show?} type="hidden" name={@field.name} value={@current || ""} />
    """
  end

  @doc """
  The empty option of a placement's select, naming what it inherits: the
  video's own quality when it has one.
  """
  def inherit_label(video) do
    case video && Playback.normalize(Map.get(video, :quality)) do
      nil -> gettext("Video’s setting")
      quality -> gettext("Video’s setting (%{quality})", quality: Playback.label(quality))
    end
  end
end
