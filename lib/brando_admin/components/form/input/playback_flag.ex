defmodule BrandoAdmin.Components.Form.Input.PlaybackFlag do
  @moduledoc """
  A video playback setting (autoplay, lazy load, loop …) as Default / On /
  Off: the video drawer, and a module's video ref and media ref templates.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  @doc """
  A playback flag has three states, not two: unset leaves it to whatever
  shows the video (`Brando.HTML.Video` and the template's opts), which a
  switch can only show as off, and whose hidden input then stores that off
  as an explicit false, which beats the template. A blank radio casts back
  to nil.
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true

  def choice(assigns) do
    assigns = assign(assigns, :current, value(assigns.field.value))

    ~H"""
    <fieldset class="playback-flag">
      <legend>{@label}</legend>
      <div class="playback-flag-options">
        <label :for={{value, text} <- [{"", gettext("Default")}, {"true", gettext("On")}, {"false", gettext("Off")}]}>
          <input type="radio" name={@field.name} value={value} checked={@current == value} />
          <span>{text}</span>
        </label>
      </div>
    </fieldset>
    """
  end

  defp value(value) when value in [true, "true"], do: "true"
  defp value(value) when value in [false, "false"], do: "false"
  defp value(_), do: ""
end
