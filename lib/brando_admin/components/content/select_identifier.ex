defmodule BrandoAdmin.Components.Content.SelectIdentifier do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content.List.Row
  alias BrandoAdmin.Components.Form.Input

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:field, fn -> nil end)
     |> assign_new(:selected_identifier_id, fn ->
       case assigns do
         %{field: %{} = field} ->
           changeset = field.form.source
           Ecto.Changeset.get_field(changeset, field.field)

         %{selected_identifier_id: id} ->
           id

         _ ->
           nil
       end
     end)
     |> assign_new(:selected_identifier, fn
       %{selected_identifier_id: nil} -> nil
       %{selected_identifier_id: id} -> Brando.Content.get_identifier!(id)
     end)
     |> assign_new(:on_change, fn -> nil end)
     |> assign_new(:wanted_schemas, fn -> [] end)
     |> assign_new(:var_key, fn -> nil end)
     |> assign_new(:var_type, fn -> nil end)
     |> assign_new(:language, fn -> nil end)
     |> assign_new(:layout, fn -> :default end)
     |> assign_new(:statuses, fn -> nil end)
     |> assign_available_schemas()
     |> assign_selected_schema()}
  end

  def assign_available_schemas(socket) do
    wanted_schemas = socket.assigns.wanted_schemas

    assign_new(socket, :available_schemas, fn -> schema_options(wanted_schemas) end)
  end

  defp schema_options([]) do
    :include_brando
    |> Brando.Content.Identifier.Registry.list_persistent_identifier_modules()
    |> Enum.map(&{Brando.Blueprint.get_plural(&1), &1})
  end

  # `wanted_schemas` arrives as module atoms, strings or path lists — normalise to
  # module atoms so the rest of the component only deals with one shape.
  defp schema_options(wanted_schemas) do
    Enum.map(wanted_schemas, fn schema ->
      module = Module.concat(List.wrap(schema))
      {Brando.Blueprint.get_plural(module), module}
    end)
  end

  # A single available schema has nothing to pick between, so preselect it and
  # load its entries up front — `entries_list` renders as soon as a schema is
  # selected and reads `@identifiers`.
  def assign_selected_schema(%{assigns: %{available_schemas: [{_label, schema_module}]}} = socket) do
    socket
    |> assign_new(:selected_schema, fn -> schema_module end)
    |> assign_new(:selected_schema_raw, fn -> to_string(schema_module) end)
    |> assign_new(:identifiers, fn ->
      {:ok, identifiers} =
        list_identifiers_for_schema(
          schema_module,
          socket.assigns.language,
          socket.assigns.statuses
        )

      identifiers
    end)
  end

  def assign_selected_schema(socket) do
    socket
    |> assign_new(:selected_schema, fn -> nil end)
    |> assign_new(:selected_schema_raw, fn -> nil end)
    |> assign_new(:identifiers, fn -> [] end)
  end

  def render(assigns) do
    ~H"""
    <div>
      <%= if @layout == :columns && @selected_schema do %>
        <div class="panels">
          <div class="panel">
            <div :if={@selected_identifier} class="selected-identifier">
              <h2 class="titlecase">{gettext("Current selected identifier")}</h2>
              <.identifier identifier={@selected_identifier} />
            </div>
            <h2 class="titlecase">{gettext("Select content type")}</h2>
            <.schema_buttons
              available_schemas={@available_schemas}
              selected_schema_raw={@selected_schema_raw}
              myself={@myself}
            />
          </div>
          <div class="panel">
            <.entries_list
              id={@id}
              identifiers={@identifiers}
              selected_identifier_id={@selected_identifier_id}
              myself={@myself}
            />
          </div>
        </div>
      <% else %>
        <div :if={@selected_identifier} class="selected-identifier">
          <h2 class="titlecase">{gettext("Current selected identifier")}</h2>
          <.identifier identifier={@selected_identifier} />
        </div>
        <h2 class="titlecase">{gettext("Select content type")}</h2>
        <.schema_buttons
          available_schemas={@available_schemas}
          selected_schema_raw={@selected_schema_raw}
          myself={@myself}
        />

        <%= if @selected_schema do %>
          <.entries_list
            id={@id}
            identifiers={@identifiers}
            selected_identifier_id={@selected_identifier_id}
            myself={@myself}
          />
        <% end %>
      <% end %>

      <Input.input :if={@field} type={:hidden} field={@field} value={@selected_identifier_id} publish />
    </div>
    """
  end

  defp schema_buttons(assigns) do
    ~H"""
    <div class="button-group-vertical tiny">
      <button
        :for={{label, schema} <- @available_schemas}
        :key={schema}
        type="button"
        class={["secondary", @selected_schema_raw == to_string(schema) && "selected"]}
        phx-click={JS.push("select_schema", target: @myself)}
        phx-value-schema={schema}
      >
        {label}
      </button>
    </div>
    """
  end

  defp entries_list(assigns) do
    ~H"""
    <div>
      <h2 class="titlecase">{gettext("Available entries")}</h2>

      <div
        id={"#{@id}-select-modal-filter"}
        class="select-filter"
        phx-hook="Brando.SelectFilter"
        data-target=".identifier"
        data-filter-target={"##{@id}-identifier-options"}
      >
        <div class="field-wrapper">
          <div class="label-wrapper">
            <label for={"#{@id}-identifier-filter"} class="control-label">
              <span>{gettext("Filter identifiers")}</span>
            </label>
          </div>
          <div class="field-base">
            <div class="filter-input-wrapper">
              <svg class="filter-icon" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
                <circle cx="7" cy="7" r="5" stroke="currentColor" stroke-width="1.5" />
                <line x1="10.75" y1="10.75" x2="14.5" y2="14.5" stroke="currentColor" stroke-width="1.5" />
              </svg>
              <input
                class="text"
                id={"#{@id}-identifier-filter"}
                name="identifier-filter"
                type="text"
                value=""
                placeholder={gettext("Filter identifiers…")}
                autocomplete="off"
              />
              <button type="button" class="filter-clear" aria-label={gettext("Clear filter")} tabindex="-1">
                <svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <line x1="2" y1="2" x2="14" y2="14" stroke="currentColor" stroke-width="1.5" />
                  <line x1="2" y1="14" x2="14" y2="2" stroke="currentColor" stroke-width="1.5" />
                </svg>
              </button>
            </div>
          </div>
        </div>
      </div>

      <div id={"#{@id}-identifier-options"} class="identifier-options">
        <div class="no-results">{gettext("No matching identifiers")}</div>
        <.identifier
          :for={identifier <- @identifiers}
          :key={identifier.id}
          identifier={identifier}
          selected_identifier_id={@selected_identifier_id}
          select={JS.push("select_identifier", target: @myself, value: %{id: identifier.id})}
        />
      </div>
    </div>
    """
  end

  attr :identifier, :any, required: true
  attr :selected_identifier_id, :integer, default: nil
  attr :select, :any, default: false
  slot :delete

  def identifier(assigns) do
    identifier = assigns.identifier
    schema = identifier.schema

    translated_type = Brando.Blueprint.get_singular(schema)

    assigns =
      assigns
      |> assign(:identifier, identifier)
      |> assign(:has_cover?, Map.has_key?(identifier, :cover))
      |> assign(:type, String.upcase(translated_type))

    ~H"""
    <button
      type="button"
      data-id={@identifier.id}
      class={[
        "identifier",
        @select && "selectable",
        @identifier.id == @selected_identifier_id && "selected"
      ]}
      data-label={@identifier.title}
      phx-click={@select}
      phx-value-param={@identifier.id}
    >
      <section class="cover-wrapper">
        <div class="cover">
          <img src={(@has_cover? && @identifier.cover) || "/images/admin/avatar.svg"} />
        </div>
      </section>
      <section class="content">
        <div class="info">
          <div class="name">
            <%= if @identifier.language do %>
              [{@identifier.language}]
            <% end %>
            {@identifier.title}
          </div>
          <div class="meta-info">
            <Row.status_circle status={@identifier.status} /> {@type}#{Brando.HTML.zero_pad(@identifier.entry_id)}
            <span>|</span> {Brando.Utils.Datetime.format_datetime(@identifier.updated_at)} [iid:{@identifier.id}]
          </div>
        </div>
      </section>
      <div class="remove">
        {render_slot(@delete)}
      </div>
    </button>
    """
  end

  def handle_event("select_schema", %{"schema" => schema}, socket) do
    schema_module = Module.concat([schema])

    {:ok, identifiers} =
      list_identifiers_for_schema(schema_module, socket.assigns.language, socket.assigns.statuses)

    {:noreply,
     socket
     |> assign(:identifiers, identifiers)
     |> assign(:selected_schema, schema_module)
     |> assign(:selected_schema_raw, schema)}
  end

  def handle_event("select_identifier", %{"id" => id}, socket) do
    {:ok, identifier} = Brando.Content.get_identifier(id)

    on_change = socket.assigns.on_change

    if on_change do
      var_key = socket.assigns.var_key
      var_type = socket.assigns.var_type

      params = %{
        event: "update_block_var",
        var_key: var_key,
        var_type: var_type,
        data: %{identifier: identifier}
      }

      on_change.(params)
    end

    socket
    |> assign(:selected_identifier, identifier)
    |> assign(:selected_identifier_id, id)
    |> then(&{:noreply, &1})
  end

  defp list_identifiers_for_schema(schema_module, language, statuses) do
    import Ecto.Query, only: [from: 2, where: 3]

    query =
      from(t in Brando.Content.Identifier,
        where: t.schema == ^schema_module,
        order_by: [asc: t.language, asc: t.title]
      )

    query =
      if language do
        where(query, [t], t.language == ^language or is_nil(t.language))
      else
        query
      end

    query =
      if statuses do
        where(query, [t], t.status in ^statuses)
      else
        query
      end

    {:ok, Brando.Repo.all(query)}
  end
end
