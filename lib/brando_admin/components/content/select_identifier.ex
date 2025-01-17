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
     |> assign_new(:selected_schema, fn -> nil end)
     |> assign_new(:selected_schema_raw, fn -> nil end)
     |> assign_new(:selected_identifier_id, fn ->
       changeset = assigns.field.form.source
       Ecto.Changeset.get_field(changeset, assigns.field.field)
     end)
     |> assign_new(:selected_identifier, fn
       %{selected_identifier_id: nil} -> nil
       %{selected_identifier_id: id} -> Brando.Content.get_identifier!(id)
     end)
     |> assign_new(:on_change, fn -> nil end)
     |> assign_new(:wanted_schemas, fn -> [] end)
     |> assign_new(:var_key, fn -> nil end)
     |> assign_new(:var_type, fn -> nil end)
     |> assign_available_schemas()
     |> assign_selected_schema()}
  end

  def assign_available_schemas(socket) do
    wanted_schemas = socket.assigns.wanted_schemas

    assign_new(socket, :available_schemas, fn ->
      if wanted_schemas == [] do
        all_relevant_types =
          :include_brando
          |> Brando.Blueprint.list_blueprints()
          |> Enum.filter(&(Brando.Content.has_identifier(&1) == {:ok, :has_identifier}))
          |> Enum.filter(&(Brando.Content.persist_identifier(&1) == {:ok, :persist_identifier}))

        Enum.map(all_relevant_types, &{Brando.Blueprint.get_plural(&1), &1})
      else
        Enum.map(wanted_schemas, &{Brando.Blueprint.get_plural(Module.concat(List.wrap(&1))), &1})
      end
    end)
  end

  def assign_selected_schema(%{assigns: %{available_schemas: available_schemas}} = socket)
      when length(available_schemas) == 1 do
    assign_new(socket, :selected_schema, fn -> List.first(available_schemas) end)
  end

  def assign_selected_schema(socket) do
    assign_new(socket, :selected_schema, fn -> nil end)
  end

  def render(assigns) do
    ~H"""
    <div>
      <div :if={@selected_identifier} class="selected-identifier">
        <h2 class="titlecase">{gettext("Current selected identifier")}</h2>
        <.identifier identifier={@selected_identifier} />
      </div>
      <h2 class="titlecase">{gettext("Select content type")}</h2>
      <div class="button-group-vertical tiny">
        <button
          :for={{label, schema} <- @available_schemas}
          type="button"
          class={["secondary", @selected_schema_raw == schema && "selected"]}
          phx-click={JS.push("select_schema", target: @myself)}
          phx-value-schema={schema}
        >
          {label}
        </button>
      </div>
      <%= if @selected_schema do %>
        <h2 class="titlecase">{gettext("Available entries")}</h2>

        <div
          id={"#{@id}-select-modal-filter"}
          class="select-filter"
          phx-hook="Brando.SelectFilter"
          data-target=".identifier"
        >
          <div class="field-wrapper">
            <div class="label-wrapper">
              <label for="identifier-filter" class="control-label">
                <span>{gettext("Filter identifiers")}</span>
              </label>
            </div>
            <div class="field-base">
              <input class="text" name="identifier-filter" type="text" value="" />
            </div>
          </div>
        </div>

        <div class="identifier-options">
          <.identifier
            :for={identifier <- @identifiers}
            identifier={identifier}
            selected_identifier_id={@selected_identifier_id}
            select={JS.push("select_identifier", target: @myself, value: %{id: identifier.id})}
          />
        </div>
      <% end %>
      <Input.input type={:hidden} field={@field} value={@selected_identifier_id} publish />
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
      phx-page-loading
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
            <Row.status_circle status={@identifier.status} /> {@type}#{Brando.HTML.zero_pad(
              @identifier.entry_id
            )}
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
    {:ok, identifiers} = Brando.Blueprint.Identifier.list_entries_for(schema_module, %{})

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
end
