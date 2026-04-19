defmodule BrandoAdmin.Components.Form.Input.IdentityTypeConfig do
  @moduledoc """
  Custom `inputs_for` component for Identity type-specific configuration.

  Reads the parent Identity form's `:type` value and renders only the
  relevant TypeConfig fields for that identity type.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form

  # Fields to show per identity type.
  # Maps identity type -> list of {field_name, input_type, label, opts} tuples.
  @type_fields %{
    "organization" => [
      {:founding_date, :date, "Founding date", []},
      {:number_of_employees, :number, "Number of employees", []}
    ],
    "corporation" => [
      {:founding_date, :date, "Founding date", []},
      {:number_of_employees, :number, "Number of employees", []},
      {:ticker_symbol, :text, "Ticker symbol", []}
    ],
    "professional_service" => [
      {:founding_date, :date, "Founding date", []},
      {:area_served, :text, "Area served", []},
      {:knows_about, :text, "Knows about", []}
    ],
    "local_business" => [
      {:opening_hours, :text, "Opening hours", [instructions: "e.g. Mo-Fr 09:00-17:00"]},
      {:price_range, :text, "Price range", [instructions: "e.g. $$, $$$"]},
      {:area_served, :text, "Area served", []},
      {:geo_latitude, :text, "Latitude", []},
      {:geo_longitude, :text, "Longitude", []}
    ],
    "restaurant" => [
      {:opening_hours, :text, "Opening hours", [instructions: "e.g. Mo-Fr 09:00-17:00"]},
      {:price_range, :text, "Price range", [instructions: "e.g. $$, $$$"]},
      {:serves_cuisine, :text, "Serves cuisine", []},
      {:has_menu, :text, "Menu URL", []},
      {:geo_latitude, :text, "Latitude", []},
      {:geo_longitude, :text, "Longitude", []}
    ]
  }

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    identity_type =
      assigns.field.form.source
      |> Ecto.Changeset.get_field(:type)
      |> to_string()

    fields = Map.get(@type_fields, identity_type, [])

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
        <input type={input_type(@type)} id={@config[@name].id} name={@config[@name].name} value={@config[@name].value || ""} />
      </Form.field_base>
    </div>
    """
  end

  defp input_type(:number), do: "number"
  defp input_type(:date), do: "date"
  defp input_type(_), do: "text"
end
