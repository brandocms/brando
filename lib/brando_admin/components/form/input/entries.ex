defmodule BrandoAdmin.Components.Form.Input.Entries do
  use BrandoAdmin, :live_component
  use Phoenix.HTML

  import Brando.Gettext
  import Brando.Utils.Datetime, only: [format_datetime: 1]

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Content.List.Row

  alias Ecto.Changeset

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

    identifiers =
      case assigns.field.value do
        "" -> []
        val -> val
      end

    selected_identifiers =
      identifiers
      |> process_identifiers()

    selected_identifiers_forms = inputs_for(assigns.field.form, assigns.field.field)
    wanted_schemas = Keyword.get(assigns.opts, :for)

    if !wanted_schemas do
      raise Brando.Exception.BlueprintError,
        message: """
        Missing `for` option for `:entries` field `#{inspect(assigns.field.field)}`

            input :related_entries, :entries, for: [
              {MyApp.Projects.Project, %{preload: [:category]}},
              {Brando.Pages.Page, %{}}
            ]

        """
    end

    {:ok,
     socket
     |> assign(assigns)
     |> prepare_input_component()
     |> assign(:selected_identifiers, selected_identifiers)
     |> assign(:selected_identifiers_forms, selected_identifiers_forms)
     |> assign_available_schemas(wanted_schemas)
     |> assign_selected_schema()
     |> assign(value: value)}
  end

  defp process_identifiers(identifiers) do
    identifiers
    |> Enum.map(fn
      %Brando.Content.Identifier{} = identifier -> identifier
      %Changeset{action: :replace} -> nil
      %Changeset{} = changeset -> Changeset.apply_changes(changeset)
      _ -> nil
    end)
    |> Enum.reject(&(&1 == nil))
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
    <div>
      <Form.field_base
        field={@field}
        label={@label}
        instructions={@instructions}
        class={@class}
        compact={@compact}>
        <%= if Enum.empty?(@selected_identifiers) do %>
          <div class="empty-list">
            <%= gettext("No selected entries") %>
          </div>
          <input type="hidden" name={@field.name} value="" />
        <% else %>
          <.inputs_for
            field={@field}
            :let={identifier_form}>
            <Input.input type={:hidden} field={identifier_form[:id]} />
            <Input.input type={:hidden} field={identifier_form[:schema]} />
            <Input.input type={:hidden} field={identifier_form[:status]} />
            <Input.input type={:hidden} field={identifier_form[:title]} />
            <Input.input type={:hidden} field={identifier_form[:cover]} />
            <Input.input type={:hidden} field={identifier_form[:type]} />
            <Input.input type={:hidden} field={identifier_form[:absolute_url]} />
            <Input.input type={:hidden} field={identifier_form[:updated_at]} />
          </.inputs_for>
        <% end %>

        <div
          id={"sortable-#{@field.id}-identifiers"}
          class="selected-entries"
          phx-hook="Brando.Sortable"
          data-target={@myself}
          data-sortable-id={"sortable-#{@field.id}-identifiers"}
          data-sortable-handle=".sort-handle"
          data-sortable-selector=".identifier">
          <.identifier
            :for={{selected_identifier, idx} <- Enum.with_index(@selected_identifiers)}
            identifier={selected_identifier}
            remove={JS.push("remove_identifier", target: @myself)}
            param={idx}
          />
        </div>

        <button type="button" class="add-entry-button" phx-click={show_modal("##{@field.id}-select-entries")}>
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M18 15l-.001 3H21v2h-3.001L18 23h-2l-.001-3H13v-2h2.999L16 15h2zm-7 3v2H3v-2h8zm10-7v2H3v-2h18zm0-7v2H3V4h18z" fill="rgba(252,245,243,1)"/></svg>
          <%= gettext("Select entries") %>
        </button>

        <Content.modal title={gettext("Select entries")} id={"#{@field.id}-select-entries"} narrow>
          <h2 class="titlecase"><%= gettext("Select content type") %></h2>
          <div class="button-group-vertical">
          <button
            :for={{label, schema, _} <- @available_schemas}
            type="button"
            class="secondary"
            phx-click={JS.push("select_schema", target: @myself)}
            phx-value-schema={schema}>
            <%= label %>
          </button>
          </div>
          <%= if !Enum.empty?(@identifiers) do %>
            <h2 class="titlecase"><%= gettext("Available entries") %></h2>
            <.identifier
              :for={{identifier, idx} <- Enum.with_index(@identifiers)}
              identifier={identifier}
              select={JS.push("select_identifier", target: @myself)}
              selected_identifiers={@selected_identifiers}
              param={idx}
            />
          <% end %>
        </Content.modal>
      </Form.field_base>
    </div>
    """
  end

  def handle_event(
        "select_identifier",
        %{"param" => idx},
        %{
          assigns: %{
            field: field,
            identifiers: identifiers,
            selected_identifiers: selected_identifiers
          }
        } = socket
      ) do
    field_name = field.field
    form = field.form
    changeset = form.source
    selected_identifier = Enum.at(identifiers, String.to_integer(idx))

    updated_identifiers =
      case Enum.find(selected_identifiers, &(&1 == selected_identifier)) do
        nil -> selected_identifiers ++ List.wrap(selected_identifier)
        _ -> Enum.reject(selected_identifiers, &(&1 == selected_identifier))
      end

    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    updated_changeset = Changeset.put_embed(changeset, field_name, updated_identifiers)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event(
        "remove_identifier",
        %{"param" => idx},
        %{
          assigns: %{
            field: field,
            selected_identifiers: selected_identifiers
          }
        } = socket
      ) do
    field_name = field.field
    form = field.form
    changeset = form.source
    {_, new_list} = List.pop_at(selected_identifiers, String.to_integer(idx))

    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    updated_changeset = Changeset.put_embed(changeset, field_name, new_list)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

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

  def handle_event(
        "sequenced",
        %{"ids" => ordered_ids},
        %{
          assigns: %{
            field: field,
            selected_identifiers: selected_identifiers
          }
        } = socket
      ) do
    field_name = field.field
    form = field.form
    changeset = form.source
    current_data = Changeset.get_change(changeset, field_name)
    applied_data = Enum.map(current_data, &Changeset.apply_changes/1)
    deduped_data = Enum.dedup(applied_data)
    sorted_data = Enum.map(ordered_ids, fn id -> Enum.find(deduped_data, &(&1.id == id)) end)

    updated_changeset = Changeset.put_change(changeset, field_name, sorted_data)

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: true
    )

    updated_identifiers =
      Enum.map(ordered_ids, fn id -> Enum.find(selected_identifiers, &(&1.id == id)) end)

    {:noreply, assign(socket, :selected_identifiers, updated_identifiers)}
  end

  def identifier(%{identifier: identifier} = assigns) when not is_nil(identifier) do
    assigns =
      assigns
      |> assign(:has_cover?, Map.has_key?(identifier, :cover))
      |> assign_new(:select, fn -> false end)
      |> assign_new(:remove, fn -> false end)
      |> assign_new(:selected_identifiers, fn -> [] end)

    ~H"""
    <article
      data-id={@identifier.id}
      class={render_classes([
        draggable: true,
        identifier: true,
        selectable: @select,
        selected: @identifier in @selected_identifiers,
        "sort-handle": true
      ])}
      phx-page-loading
      phx-click={@select}
      phx-value-param={@param}>

      <section class="cover-wrapper">
        <div class="cover">
          <img src={@has_cover? && @identifier.cover || "/images/admin/avatar.svg"}>
        </div>
      </section>
      <section class="content">
        <div class="info">
          <div class="name">
            <%= @identifier.title %>
          </div>
          <div class="meta-info">
            <Row.status_circle status={@identifier.status} /> <%= @identifier.type %>#<%= Brando.HTML.zero_pad(@identifier.id) %> <span>|</span> <%= format_datetime(@identifier.updated_at) %>
          </div>
        </div>
      </section>
      <%= if @remove do %>
        <div class="remove">
          <button type="button" phx-page-loading phx-click={@remove} phx-value-param={@param}>
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" width="20" height="20">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      <% end %>
    </article>
    """
  end

  def identifier(%{identifier_form: identifier_form} = assigns)
      when not is_nil(identifier_form) do
    assigns =
      assigns
      |> assign_new(:select, fn -> false end)
      |> assign_new(:remove, fn -> false end)
      |> assign_new(:selected_identifiers, fn -> [] end)

    ~H"""
    <article
      class={render_classes([identifier: true, selected: @identifier_form in @selected_identifiers])}
      phx-page-loading
      phx-click={@select}
      phx-value-param={@param}>

      <section class="cover-wrapper">
        <div class="cover">
          <img src={@identifier_form[:cover].value || "/images/admin/avatar.svg"}>
        </div>
      </section>
      <section class="content">
        <div class="info">
          <div class="name">
            <%= @identifier_form[:title].value %>
          </div>
          <div class="meta-info">
            <%= @identifier_form[:type].value %>
          </div>
        </div>
      </section>
      <%= if @remove do %>
        <div class="remove">
          <button type="button" phx-page-loading phx-click={@remove} phx-value-param={@param}>
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" width="20" height="20">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      <% end %>
    </article>
    """
  end

  defp get_list_opts(schema_module, available_schemas) do
    Enum.find(available_schemas, &(elem(&1, 1) == schema_module))
  end
end
