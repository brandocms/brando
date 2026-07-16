defmodule BrandoAdmin.Components.ChildListingButton do
  @moduledoc """
  Stateless child-listing toggle used by Blueprint listing rows.

  The button targets the owning listing row directly. Its visual state is applied
  through `Phoenix.LiveView.JS`, which keeps the decoration sticky across row
  patches without adding a stateful component between the Blueprint and the row.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :entry, :map, required: true
  attr :fields, :any, required: true
  attr :target, :any, required: true
  attr :text, :string, default: nil

  @doc "Renders a toggle for the configured child associations."
  def children_button(assigns) do
    fields = List.wrap(assigns.fields)
    button_id = "children-button-#{assigns.entry.id}"

    assigns =
      assigns
      |> assign(:button_id, button_id)
      |> assign(:count, count_children(assigns.entry, fields))
      |> assign(:toggle, toggle(button_id, assigns.target, fields))

    ~H"""
    <div class={["children-button", @count == 0 && "hidden"]}>
      <button
        id={@button_id}
        type="button"
        phx-click={@toggle}
        data-testid="children-button"
        class={@text && "text"}
        aria-expanded="false"
      >
        <span class="children-button-count">+ {@count}</span>
        <span class="children-button-close">{Gettext.gettext(Brando.Gettext, "Close")}</span>
        <span :if={@text} class="children-button-text">{@text}</span>
      </button>
    </div>
    """
  end

  defp toggle(button_id, target, fields) do
    selector = "##{button_id}"
    event_fields = Enum.map(fields, &to_string/1)

    JS.toggle_class("active", to: selector)
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: selector)
    |> JS.push("toggle_children", target: target, value: %{fields: event_fields})
  end

  defp count_children(entry, fields) do
    Enum.reduce(fields, 0, fn field, count ->
      count + Enum.count(Map.get(entry, field) || [])
    end)
  end
end
