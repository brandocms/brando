defmodule BrandoAdmin.Components.Form.Input.IdentityTypeConfig do
  @moduledoc """
  Custom `inputs_for` component for Identity type-specific configuration.

  Reads the parent Identity form's `:type` value and renders only the
  relevant TypeConfig fields for that identity type. Includes a structured
  opening hours grid for LocalBusiness, Restaurant, and ArtGallery types.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input

  @days [
    {"monday", "Monday"},
    {"tuesday", "Tuesday"},
    {"wednesday", "Wednesday"},
    {"thursday", "Thursday"},
    {"friday", "Friday"},
    {"saturday", "Saturday"},
    {"sunday", "Sunday"}
  ]

  @opening_hours_types ["local_business", "restaurant", "art_gallery"]

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    identity_type =
      assigns.field.form.source
      |> Ecto.Changeset.get_field(:type)
      |> to_string()

    fields = type_fields(identity_type)
    has_opening_hours = identity_type in @opening_hours_types

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:identity_type, identity_type)
     |> assign(:type_fields, fields)
     |> assign(:has_opening_hours, has_opening_hours)
     |> assign(:days, @days)}
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
          <div :if={@has_opening_hours} class="opening-hours-grid">
            <h3 class="opening-hours-title">{gettext("Opening hours")}</h3>
            <.opening_hours_row
              :for={{day_key, day_label} <- @days}
              config={config}
              day_key={day_key}
              day_label={day_label}
            />
          </div>
          <div :if={@type_fields == [] && !@has_opening_hours} class="type-config-empty">
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
        />
      </Form.field_base>
    </div>
    """
  end

  defp opening_hours_row(assigns) do
    spec_field = assigns.config[:opening_hours_specification]
    current_specs = spec_field.value || %{}
    day_data = Map.get(current_specs, assigns.day_key, %{})
    closed = Map.get(day_data, "closed") in [true, "true"]

    assigns =
      assigns
      |> assign(:spec_name, spec_field.name)
      |> assign(:opens, Map.get(day_data, "opens", "09:00"))
      |> assign(:closes, Map.get(day_data, "closes", "17:00"))
      |> assign(:closed, closed)

    ~H"""
    <div class="subform-entry opening-hours-row">
      <div class="opening-hours-day">
        <span class="day-label">{Gettext.gettext(Brando.Gettext, @day_label)}</span>
      </div>
      <div class={["opening-hours-times", @closed && "closed"]}>
        <input
          type="time"
          name={"#{@spec_name}[#{@day_key}][opens]"}
          value={@opens}
          disabled={@closed}
          class="text time-input"
        />
        <span class="time-separator">&ndash;</span>
        <input
          type="time"
          name={"#{@spec_name}[#{@day_key}][closes]"}
          value={@closes}
          disabled={@closed}
          class="text time-input"
        />
      </div>
      <div class="opening-hours-closed">
        <input
          type="hidden"
          name={"#{@spec_name}[#{@day_key}][closed]"}
          value="false"
        />
        <label class="closed-toggle">
          <input
            type="checkbox"
            name={"#{@spec_name}[#{@day_key}][closed]"}
            value="true"
            checked={@closed}
          />
          <span>{gettext("Closed")}</span>
        </label>
      </div>
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
      {:price_range, :text, gettext("Price range"), [instructions: gettext("e.g. $$, $$$")]},
      {:area_served, :text, gettext("Area served"), []},
      {:geo_latitude, :text, gettext("Latitude"), []},
      {:geo_longitude, :text, gettext("Longitude"), []}
    ]
  end

  defp type_fields("restaurant") do
    [
      {:price_range, :text, gettext("Price range"), [instructions: gettext("e.g. $$, $$$")]},
      {:serves_cuisine, :text, gettext("Serves cuisine"), []},
      {:has_menu, :text, gettext("Menu URL"), []},
      {:geo_latitude, :text, gettext("Latitude"), []},
      {:geo_longitude, :text, gettext("Longitude"), []}
    ]
  end

  defp type_fields("educational_organization") do
    [
      {:founding_date, :date, gettext("Founding date"), []},
      {:number_of_employees, :number, gettext("Number of employees"), []}
    ]
  end

  defp type_fields("government_organization") do
    [
      {:founding_date, :date, gettext("Founding date"), []},
      {:number_of_employees, :number, gettext("Number of employees"), []}
    ]
  end

  defp type_fields("ngo") do
    [
      {:founding_date, :date, gettext("Founding date"), []},
      {:number_of_employees, :number, gettext("Number of employees"), []}
    ]
  end

  defp type_fields("medical_organization") do
    [
      {:founding_date, :date, gettext("Founding date"), []},
      {:number_of_employees, :number, gettext("Number of employees"), []},
      {:medical_specialty, :text, gettext("Medical specialty"), []}
    ]
  end

  defp type_fields("sports_organization") do
    [
      {:founding_date, :date, gettext("Founding date"), []},
      {:number_of_employees, :number, gettext("Number of employees"), []},
      {:sport, :text, gettext("Sport"), []}
    ]
  end

  defp type_fields("art_gallery") do
    [
      {:price_range, :text, gettext("Price range"), [instructions: gettext("e.g. Free, $$")]},
      {:area_served, :text, gettext("Area served"), []},
      {:geo_latitude, :text, gettext("Latitude"), []},
      {:geo_longitude, :text, gettext("Longitude"), []}
    ]
  end

  defp type_fields("architect") do
    [
      {:founding_date, :date, gettext("Founding date"), []},
      {:area_served, :text, gettext("Area served"), []},
      {:knows_about, :text, gettext("Knows about"), []}
    ]
  end

  defp type_fields(_), do: []
end
