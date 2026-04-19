defmodule BrandoAdmin.Components.Form.Input.IdentityTypeConfig do
  @moduledoc """
  Custom `inputs_for` component for Identity type-specific configuration.

  Reads the parent Identity form's `:type` value and renders only the
  relevant TypeConfig fields for that identity type.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    identity_type =
      assigns.field.form.source
      |> Ecto.Changeset.get_field(:type)
      |> to_string()

    fields = type_fields(identity_type)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:identity_type, identity_type)
     |> assign(:type_fields, fields)}
  end

  def render(assigns) do
    ~H"""
    <fieldset>
      <Form.field_base field={@field} label={@label} instructions={@instructions} class="subform">
        <.inputs_for :let={config} field={@field}>
          <div :if={@type_fields != []} class="type-config-fields">
            <.type_field
              :for={{name, type, label, opts} <- @type_fields}
              config={config}
              name={name}
              type={type}
              label={label}
              opts={opts}
            />
          </div>
          <div :if={@type_fields == []} class="type-config-empty">
            <p>{gettext("No additional fields for this identity type.")}</p>
          </div>
        </.inputs_for>
      </Form.field_base>
    </fieldset>
    """
  end

  defp type_field(assigns) do
    instructions = Keyword.get(assigns.opts, :instructions)
    assigns = assign(assigns, :instructions, instructions)

    ~H"""
    <div class="brando-input" data-component={@type}>
      <Form.field_base field={@config[@name]} label={@label} instructions={@instructions}>
        <Input.input
          type={@type}
          field={@config[@name]}
          class={["text"]}
          phx-debounce={300}
          data-watch-focus
        />
      </Form.field_base>
    </div>
    """
  end

  # Fields per identity type. Built at runtime for gettext translation.
  # Returns list of {field_name, input_type, label, opts} tuples.
  defp type_fields("organization") do
    [
      {:founding_date, :date, gettext("Founding date"), []},
      {:number_of_employees, :number, gettext("Number of employees"), []}
    ]
  end

  defp type_fields("corporation") do
    [
      {:founding_date, :date, gettext("Founding date"), []},
      {:number_of_employees, :number, gettext("Number of employees"), []},
      {:ticker_symbol, :text, gettext("Ticker symbol"), []}
    ]
  end

  defp type_fields("professional_service") do
    [
      {:founding_date, :date, gettext("Founding date"), []},
      {:area_served, :text, gettext("Area served"), []},
      {:knows_about, :text, gettext("Knows about"), []}
    ]
  end

  defp type_fields("local_business") do
    [
      {:opening_hours, :text, gettext("Opening hours"), [instructions: gettext("e.g. Mo-Fr 09:00-17:00")]},
      {:price_range, :text, gettext("Price range"), [instructions: gettext("e.g. $$, $$$")]},
      {:area_served, :text, gettext("Area served"), []},
      {:geo_latitude, :text, gettext("Latitude"), []},
      {:geo_longitude, :text, gettext("Longitude"), []}
    ]
  end

  defp type_fields("restaurant") do
    [
      {:opening_hours, :text, gettext("Opening hours"), [instructions: gettext("e.g. Mo-Fr 09:00-17:00")]},
      {:price_range, :text, gettext("Price range"), [instructions: gettext("e.g. $$, $$$")]},
      {:serves_cuisine, :text, gettext("Serves cuisine"), []},
      {:has_menu, :text, gettext("Menu URL"), []},
      {:geo_latitude, :text, gettext("Latitude"), []},
      {:geo_longitude, :text, gettext("Longitude"), []}
    ]
  end

  defp type_fields(_), do: []
end
