defmodule BrandoAdmin.Components.Content.SelectIdentifier do
  use BrandoAdmin, :live_component
  import Brando.Gettext
  alias Brando.Utils
  alias BrandoAdmin.Components.Content.List.Row
  alias BrandoAdmin.Components.Form.Input

  def update(assigns, socket) do
    # {identifier, assigns} = Map.pop(assigns, :identifier)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:identifier, fn -> nil end)
     |> assign_new(:selected_schema, fn -> nil end)
     |> assign_new(:selected_identifier, fn -> nil end)
     |> assign_new(:selected_identifier_id, fn %{identifier: identifier} ->
       if identifier, do: identifier.id
     end)
     |> assign_new(:wanted_schemas, fn -> [] end)
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
      <div :if={@identifier} class="selected-identifier">
        <h2 class="titlecase"><%= gettext("Current selected identifier") %></h2>
        <.identifier identifier={@identifier} />
      </div>
      <h2 class="titlecase"><%= gettext("Select content type") %></h2>
      <div class="button-group-vertical tiny">
        <button
          :for={{label, schema} <- @available_schemas}
          type="button"
          class="secondary"
          phx-click={JS.push("select_schema", target: @myself)}
          phx-value-schema={schema}
        >
          <%= label %>
        </button>
      </div>
      <%= if @selected_schema do %>
        <h2 class="titlecase"><%= gettext("Available entries") %></h2>
        <.identifier
          :for={identifier <- @identifiers}
          identifier={identifier}
          select={JS.push("select_identifier", target: @myself, value: %{id: identifier.id})}
        />
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

    translated_type =
      Utils.try_path(schema.__translations__(), [:naming, :singular]) ||
        schema.__naming__().singular

    assigns =
      assigns
      |> assign(:identifier, identifier)
      |> assign(:has_cover?, Map.has_key?(identifier, :cover))
      |> assign(:type, String.upcase(translated_type))

    ~H"""
    <article
      data-id={@identifier.id}
      class={[
        "identifier",
        @select && "selectable",
        @identifier.id == @selected_identifier_id && "selected"
      ]}
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
              [<%= @identifier.language %>]
            <% end %>
            <%= @identifier.title %>
          </div>
          <div class="meta-info">
            <Row.status_circle status={@identifier.status} /> <%= @type %>#<%= Brando.HTML.zero_pad(
              @identifier.entry_id
            ) %>
            <span>|</span> <%= Brando.Utils.Datetime.format_datetime(@identifier.updated_at) %> [iid:<%= @identifier.id %>]
          </div>
        </div>
      </section>
      <div class="remove">
        <%= render_slot(@delete) %>
      </div>
    </article>
    """
  end

  def handle_event("select_schema", %{"schema" => schema}, socket) do
    schema_module = Module.concat([schema])
    {:ok, identifiers} = Brando.Blueprint.Identifier.list_entries_for(schema_module, %{})

    {:noreply,
     socket
     |> assign(:identifiers, identifiers)
     |> assign(:selected_schema, schema_module)}
  end

  def handle_event("select_identifier", %{"id" => id}, socket) do
    # {:ok, identifier} = Brando.Content.get_identifier(id)

    socket
    # |> assign(:identifier, identifier)
    |> assign(:selected_identifier_id, id)
    |> then(&{:noreply, &1})
  end
end
