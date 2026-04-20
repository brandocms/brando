defmodule BrandoAdmin.Components.Form.Input.IdentityTypeConfig do
  @moduledoc """
  Custom `inputs_for` component for Identity type-specific configuration.

  Reads the parent Identity form's `:type` value and renders only the
  relevant TypeConfig fields for that identity type. Includes a structured
  opening hours grid for LocalBusiness and Restaurant types.
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

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    identity_type =
      assigns.field.form.source
      |> Ecto.Changeset.get_field(:type)
      |> to_string()

    fields = type_fields(identity_type)
    has_opening_hours = identity_type in ["local_business", "restaurant"]

    opening_hours =
      if has_opening_hours do
        assigns.field.form.source
        |> Ecto.Changeset.get_field(:type_config)
        |> case do
          %{opening_hours_specification: specs} when is_list(specs) and specs != [] -> specs
          _ -> default_opening_hours()
        end
      else
        []
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:identity_type, identity_type)
     |> assign(:type_fields, fields)
     |> assign(:has_opening_hours, has_opening_hours)
     |> assign(:opening_hours, opening_hours)
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
          <div :if={@has_opening_hours} class="type-config-opening-hours">
            <.opening_hours_grid
              config={config}
              opening_hours={@opening_hours}
              days={@days}
              myself={@myself}
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

  defp opening_hours_grid(assigns) do
    ~H"""
    <div class="opening-hours-grid">
      <h3 class="opening-hours-title">{gettext("Opening hours")}</h3>
      <div :for={{day_key, day_label} <- @days} class="opening-hours-row">
        <% day_data = find_day(@opening_hours, day_label) %>
        <% closed = Map.get(day_data, "closed", false) %>
        <div class="opening-hours-day">
          <span class="day-label">{Gettext.gettext(Brando.Gettext, day_label)}</span>
        </div>
        <div class={["opening-hours-times", closed && "closed"]}>
          <input
            type="time"
            name={"#{@config[:opening_hours_specification].name}[#{day_key}][opens]"}
            value={Map.get(day_data, "opens", "")}
            disabled={closed}
            class="text time-input"
          />
          <span class="time-separator">&ndash;</span>
          <input
            type="time"
            name={"#{@config[:opening_hours_specification].name}[#{day_key}][closes]"}
            value={Map.get(day_data, "closes", "")}
            disabled={closed}
            class="text time-input"
          />
        </div>
        <div class="opening-hours-closed">
          <label class="closed-toggle">
            <input
              type="checkbox"
              name={"#{@config[:opening_hours_specification].name}[#{day_key}][closed]"}
              value="true"
              checked={closed}
              phx-click={JS.push("toggle_day_closed", target: @myself, value: %{day: day_label})}
            />
            <span>{gettext("Closed")}</span>
          </label>
        </div>
        <input
          type="hidden"
          name={"#{@config[:opening_hours_specification].name}[#{day_key}][day]"}
          value={day_label}
        />
      </div>
    </div>
    """
  end

  def handle_event("toggle_day_closed", %{"day" => day}, socket) do
    opening_hours =
      Enum.map(socket.assigns.opening_hours, fn spec ->
        if Map.get(spec, "days") == [day] or Map.get(spec, "day") == day do
          Map.update(spec, "closed", true, &(!&1))
        else
          spec
        end
      end)

    {:noreply, assign(socket, :opening_hours, opening_hours)}
  end

  defp find_day(specs, day_label) do
    Enum.find(specs, %{}, fn spec ->
      day_label in List.wrap(Map.get(spec, "days", [])) or
        Map.get(spec, "day") == day_label
    end)
  end

  defp default_opening_hours do
    Enum.map(@days, fn {_key, label} ->
      %{"days" => [label], "opens" => "09:00", "closes" => "17:00", "closed" => false}
    end)
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

  defp type_fields(_), do: []
end
