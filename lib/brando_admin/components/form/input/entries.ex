defmodule BrandoAdmin.Components.Form.Input.Entries do
  use BrandoAdmin, :live_component
  use Phoenix.HTML

  import Brando.Gettext

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.FieldBase
  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Components.Identifier

  # prop form, :form
  # prop field, :atom
  # prop label, :string
  # prop instructions, :string
  # prop opts, :list, default: []
  # prop current_user, :map
  # prop uploads, :map
  # prop value, :any

  # data available_schemas, :list
  # data identifiers, :list
  # data selected_identifiers, :list
  # data class, :string
  # data compact, :boolean

  def mount(socket) do
    {:ok, assign(socket, identifiers: [])}
  end

  def update(assigns, socket) do
    value = assigns[:value]

    selected_identifiers =
      assigns.form
      |> input_value(assigns.field)
      |> Enum.map(fn
        %Brando.Content.Identifier{} = identifier ->
          identifier

        %Ecto.Changeset{action: :replace} ->
          nil

        %Ecto.Changeset{} = changeset ->
          Ecto.Changeset.apply_changes(changeset)
      end)
      |> Enum.reject(&(&1 == nil))

    selected_identifiers_forms = inputs_for(assigns.form, assigns.field)
    wanted_schemas = Keyword.get(assigns.opts, :for)

    if !wanted_schemas do
      raise Brando.Exception.BlueprintError,
        message: """
        Missing `for` option for `:entries` field `#{inspect(assigns.field)}`

            input :related_entries, :entries, for: [
              {MyApp.Projects.Project, %{preload: [:category]}},
              {Brando.Pages.Page, %{}}
            ]

        """
    end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:selected_identifiers, selected_identifiers)
     |> assign(:selected_identifiers_forms, selected_identifiers_forms)
     |> assign_available_schemas(wanted_schemas)
     |> assign_selected_schema()
     |> assign(value: value)}
  end

  def assign_available_schemas(socket, wanted_schemas) do
    assign_new(socket, :available_schemas, fn ->
      Brando.Blueprint.Identifier.get_entry_types(wanted_schemas)
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
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <%= if Enum.empty?(@selected_identifiers) do %>
        <div class="empty-list">
          <%= gettext("No selected entries") %>
        </div>
      <% end %>

      <Form.inputs
        form={@form}
        for={@field}
        :let={form: identifier_form}>
        <%= hidden_input identifier_form, :id %>
        <%= hidden_input identifier_form, :schema %>
        <%= hidden_input identifier_form, :status %>
        <%= hidden_input identifier_form, :title %>
        <%= hidden_input identifier_form, :cover %>
        <%= hidden_input identifier_form, :type %>
        <%= hidden_input identifier_form, :absolute_url %>
      </Form.inputs>

      <%= for {selected_identifier, idx} <- Enum.with_index(@selected_identifiers) do %>
        <Identifier.render
          identifier={selected_identifier}
          remove="remove_identifier"
          param={idx}
        />
      <% end %>

      <button type="button" class="add-entry-button" :on-click="show_modal" phx-value-id={"#{@form.id}-#{@field}-select-entries"}>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M18 15l-.001 3H21v2h-3.001L18 23h-2l-.001-3H13v-2h2.999L16 15h2zm-7 3v2H3v-2h8zm10-7v2H3v-2h18zm0-7v2H3V4h18z" fill="rgba(252,245,243,1)"/></svg>
        <%= gettext("Select entries") %>
      </button>

      <Modal title="Select entries" id={"#{@form.id}-#{@field}-select-entries"} narrow>
        <h2 class="titlecase"><%= gettext("Select content type") %></h2>
        <div class="button-group-vertical">
        <%= for {label, schema, _} <- @available_schemas do %>
          <button type="button" class="secondary" :on-click="select_schema" phx-value-schema={schema}>
            <%= label %>
          </button>
        <% end %>
        </div>
        <%= if !Enum.empty?(@identifiers) do %>
          <h2 class="titlecase">{gettext("Available entries")}</h2>
          <%= for {identifier, idx} <- Enum.with_index(@identifiers) do %>
            <Identifier.render
              identifier={identifier}
              select="select_identifier"
              selected_identifiers={@selected_identifiers}
              param={idx}
            />
          <% end %>
        <% end %>
      </Modal>
    </FieldBase>
    """
  end

  def handle_event(
        "select_identifier",
        %{"param" => idx},
        %{
          assigns: %{
            field: field_name,
            form: %{source: changeset},
            identifiers: identifiers,
            selected_identifiers: selected_identifiers
          }
        } = socket
      ) do
    selected_identifier = Enum.at(identifiers, String.to_integer(idx))

    updated_identifiers =
      case Enum.find(selected_identifiers, &(&1 == selected_identifier)) do
        nil -> selected_identifiers ++ List.wrap(selected_identifier)
        _ -> Enum.reject(selected_identifiers, &(&1 == selected_identifier))
      end

    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    updated_changeset = Ecto.Changeset.put_embed(changeset, field_name, updated_identifiers)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event(
        "remove_identifier",
        %{"param" => idx},
        %{
          assigns: %{
            field: field_name,
            form: %{source: changeset},
            selected_identifiers: selected_identifiers
          }
        } = socket
      ) do
    {_, new_list} = List.pop_at(selected_identifiers, String.to_integer(idx))

    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    updated_changeset = Ecto.Changeset.put_embed(changeset, field_name, new_list)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event("show_modal", %{"id" => modal_id}, socket) do
    Modal.show(modal_id)

    {:noreply, socket}
  end

  def handle_event(
        "select_schema",
        %{"schema" => schema},
        %{assigns: %{available_schemas: available_schemas}} = socket
      ) do
    schema_module = Module.concat([schema])
    {_, _, list_opts} = get_list_opts(schema_module, available_schemas)
    {:ok, identifiers} = Brando.Blueprint.Identifier.list_entries_for(schema_module, list_opts)
    {:noreply, assign(socket, :identifiers, identifiers)}
  end

  defp get_list_opts(schema_module, available_schemas) do
    Enum.find(available_schemas, &(elem(&1, 1) == schema_module))
  end
end
