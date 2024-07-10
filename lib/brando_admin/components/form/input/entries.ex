defmodule BrandoAdmin.Components.Form.Input.Entries do
  use BrandoAdmin, :live_component

  import Brando.Gettext
  import Brando.Utils.Datetime, only: [format_datetime: 1]

  alias Brando.Utils
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

  def update(assigns, socket) do
    field = assigns.field
    schema = field.form.source.data.__struct__
    %{opts: %{module: join_schema} = field_opts} = schema.__relation__(field.field)

    wanted_schemas = Keyword.get(assigns.opts, :for)

    if !wanted_schemas do
      raise Brando.Exception.BlueprintError,
        message: """
        Missing `for` option for `:entries` field `#{inspect(field.field)}`

            input :#{inspect(field.field)}, :entries, for: [
              {MyApp.Projects.Project, %{preload: [:category]}},
              {Brando.Pages.Page, %{}}
            ]

        """
    end

    {:ok,
     socket
     |> assign(assigns)
     |> prepare_input_component()
     |> assign_new(:selected_schema, fn -> nil end)
     |> assign_new(:join_schema, fn -> join_schema end)
     |> assign_new(:selected_identifiers, fn -> Enum.map(field.value, & &1.identifier) end)
     |> assign_new(:available_identifiers, fn %{selected_identifiers: selected_identifiers} ->
       selected_identifiers
     end)
     |> assign_new(:max_length, fn -> get_in(field_opts, [:constraints, :max_length]) end)
     |> assign_new(:min_length, fn -> get_in(field_opts, [:constraints, :min_length]) end)
     |> assign_available_schemas(wanted_schemas)
     |> assign_selected_schema()}
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
        compact={@compact}
      >
        <%= if Enum.empty?(@selected_identifiers) do %>
          <div class="empty-list">
            <%= gettext("No selected entries") %>
            <input type="hidden" name={"#{@field.form.name}[drop_#{@field.field}_ids][]"} />
          </div>
        <% else %>
          <div
            id={"sortable-#{@field.id}-identifiers"}
            class="selected-entries"
            phx-hook="Brando.SortableAssocs"
            data-target={@myself}
            data-sortable-id={"sortable-#{@field.id}-identifiers"}
            data-sortable-handle=".identifier"
            data-sortable-selector=".identifier"
            data-sortable-dispatch-event="true"
            data-sortable-dispatch-event-target-id={@field.id}
            data-sortable-filter=".remove button"
          >
            <input type="hidden" name={@field.name} id={@field.id} />
            <.inputs_for :let={identifier_form} field={@field}>
              <.assoc_identifier
                assoc_identifier={identifier_form}
                available_identifiers={@selected_identifiers}
              >
                <%!-- <input
                  type="hidden"
                  name={identifier_form[:id].name}
                  value={identifier_form[:id].value}
                />
                <input
                  type="hidden"
                  name={identifier_form[:_persistent_id].name}
                  value={identifier_form.index}
                /> --%>
                <:delete>
                  <input
                    type="hidden"
                    name={"#{@field.form.name}[sort_#{@field.field}_ids][]"}
                    value={identifier_form.index}
                  />
                  <button
                    type="button"
                    name={"#{@field.form.name}[drop_#{@field.field}_ids][]"}
                    value={identifier_form.index}
                    phx-click={JS.dispatch("change")}
                  >
                    <.icon name="hero-x-circle" />
                  </button>
                </:delete>
              </.assoc_identifier>
            </.inputs_for>
            <input type="hidden" name={"#{@field.form.name}[drop_#{@field.field}_ids][]"} />
          </div>
        <% end %>

        <button type="button" class="tiny" phx-click={show_modal("##{@field.id}-select-entries")}>
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
              phx-value-schema={schema}
            >
              <%= label %>
            </button>
          </div>
          <%= if @selected_schema do %>
            <h2 class="titlecase"><%= gettext("Available entries") %></h2>
            <.assoc_identifier
              :for={identifier <- @available_identifiers}
              identifier={identifier}
              select={JS.push("select_identifier", value: %{id: identifier.id}, target: @myself)}
              available_identifiers={@available_identifiers}
              assoc_identifiers={@field}
            />
          <% end %>
        </Content.modal>
      </Form.field_base>
    </div>
    """
  end

  def handle_event("select_identifier", %{"id" => identifier_id}, socket) do
    identifiers_field = socket.assigns.field
    field_name = identifiers_field.field
    form = identifiers_field.form
    changeset = form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"
    assoc_schema = socket.assigns.join_schema
    available_identifiers = socket.assigns.available_identifiers
    selected_identifiers = socket.assigns.selected_identifiers
    max_length = socket.assigns.max_length

    selected_identifier =
      Enum.find(available_identifiers, &(to_string(&1.id) == to_string(identifier_id)))

    assoc_identifiers = Changeset.get_assoc(changeset, field_name)

    updated_assoc_identifiers =
      assoc_identifiers
      |> Enum.find(&(Changeset.get_field(&1, :identifier_id) == identifier_id))
      |> case do
        nil ->
          insert_identifier(assoc_identifiers, identifier_id, assoc_schema)

        %{action: :replace} = replaced_changeset ->
          Enum.map(assoc_identifiers, fn assoc_identifier ->
            case Changeset.get_field(assoc_identifier, :identifier_id) == identifier_id do
              true ->
                action = (Changeset.get_field(assoc_identifier, :id) == nil && :insert) || nil
                Map.put(replaced_changeset, :action, action)

              false ->
                assoc_identifier
            end
          end)

        _ ->
          remove_identifier(assoc_identifiers, identifier_id)
      end
      |> Enum.filter(&(&1.action != :replace))

    if Enum.count(updated_assoc_identifiers) > max_length do
      alert = %{
        title: gettext("Too many selections"),
        message: gettext("You can only select %{max_length} entries", max_length: max_length),
        type: "info"
      }

      socket
      |> push_event("b:alert", alert)
      |> then(&{:noreply, &1})
    else
      updated_changeset =
        Changeset.put_assoc(
          changeset,
          field_name,
          updated_assoc_identifiers
        )

      # ship this changeset off to the form component
      send_update(BrandoAdmin.Components.Form,
        id: form_id,
        action: :update_changeset,
        changeset: updated_changeset
      )

      updated_identifiers = [selected_identifier | selected_identifiers]

      # flattened_assoc_identifiers =
      #   Enum.map(updated_assoc_identifiers, fn assoc_identifier ->
      #     applied_assoc_identifier = Changeset.apply_changes(assoc_identifier)

      #     if applied_assoc_identifier.identifier_id == identifier_id do
      #       Map.put(applied_assoc_identifier, :identifier, selected_identifier)
      #     else
      #       applied_assoc_identifier
      #     end
      #   end)

      # send_update(BrandoAdmin.Components.Form,
      #   id: form_id,
      #   event: "update_entry_relation",
      #   path: [field_name],
      #   updated_relation: flattened_assoc_identifiers
      # )

      {:noreply, assign(socket, :selected_identifiers, updated_identifiers)}
    end
  end

  def handle_event(
        "select_schema",
        %{"schema" => schema},
        %{assigns: %{available_schemas: available_schemas}} = socket
      ) do
    schema_module = Module.concat([schema])
    {_, _, list_opts} = get_list_opts(schema_module, available_schemas)
    field_opts = socket.assigns.opts

    list_opts =
      case Keyword.get(field_opts, :filter_language, false) do
        false ->
          list_opts

        true ->
          form = socket.assigns.field.form
          language = form[:language]

          if language do
            language_atom = String.to_existing_atom(language.value)
            Map.put(list_opts, :language, language_atom)
          else
            list_opts
          end
      end

    {:ok, identifiers} = Brando.Blueprint.Identifier.list_entries_for(schema_module, list_opts)

    {:noreply,
     socket
     |> assign(:available_identifiers, identifiers)
     |> assign(:selected_schema, schema_module)}
  end

  attr :block_identifier, :any
  attr :identifier, :any
  attr :block_identifiers, :list, default: nil
  attr :identifier_id, :integer
  attr :available_identifiers, :list, default: []
  attr :select, :any, default: false
  slot :inner_block, default: nil
  slot :delete

  def block_identifier(%{block_identifier: block_identifier} = assigns) do
    changeset = block_identifier.source
    identifier_changeset = Changeset.get_assoc(changeset, :identifier)

    identifier =
      if identifier_changeset == nil do
        identifier_id = Changeset.get_field(changeset, :identifier_id)
        Enum.find(assigns.available_identifiers, &(&1.id == identifier_id))
      else
        identifier_changeset.data
      end

    assigns =
      assigns
      |> assign(:identifier, identifier)
      |> assign(:has_cover?, Map.has_key?(identifier, :cover))

    ~H"""
    <article
      data-id={@identifier.id}
      class={[
        "draggable",
        "identifier"
      ]}
      phx-page-loading
      phx-click={@select}
      phx-value-param={@identifier.id}
    >
      <Input.hidden field={@block_identifier[:block_id]} />
      <Input.hidden field={@block_identifier[:identifier_id]} />

      <.identifier_content has_cover?={@has_cover?} identifier={@identifier}>
        <:delete>
          <%= render_slot(@delete) %>
        </:delete>
        <%= render_slot(@inner_block) %>
      </.identifier_content>
    </article>
    """
  end

  def block_identifier(%{identifier: identifier, block_identifiers: block_identifiers} = assigns)
      when not is_nil(block_identifiers) do
    block_identifiers_changesets =
      Changeset.get_assoc(block_identifiers.form.source, :block_identifiers)

    selected =
      Enum.find(
        block_identifiers_changesets,
        &(Changeset.get_field(&1, :identifier_id) == identifier.id)
      )

    assigns =
      assigns
      |> assign(:identifier, identifier)
      |> assign(:has_cover?, Map.has_key?(identifier, :cover))
      |> assign(:selected, selected && selected.action != :replace)

    ~H"""
    <article
      data-id={@identifier.id}
      class={[
        "identifier",
        @selected && "selected"
      ]}
      phx-page-loading
      phx-click={@select}
      phx-value-param={@identifier.id}
    >
      <.identifier_content has_cover?={@has_cover?} identifier={@identifier}>
        <:delete>
          <%= render_slot(@delete) %>
        </:delete>
        <%= render_slot(@inner_block) %>
      </.identifier_content>
    </article>
    """
  end

  attr :identifier_id, :integer
  attr :available_identifiers, :list, default: []
  attr :selected_identifiers, :list, default: []
  attr :select, :any, default: false
  slot :delete

  def identifier(%{identifier_id: identifier_id} = assigns) when not is_nil(identifier_id) do
    available_identifiers = assigns.available_identifiers

    identifier =
      Enum.find(
        available_identifiers,
        &(to_string(&1.id) == to_string(identifier_id))
      )

    assigns =
      assigns
      |> assign(:identifier, identifier)
      |> assign(:has_cover?, Map.has_key?(identifier, :cover))

    ~H"""
    <article
      data-id={@identifier.id}
      class={[
        "draggable",
        "identifier",
        @select && "selectable",
        @identifier in @selected_identifiers && "selected"
      ]}
      phx-page-loading
      phx-click={@select}
      phx-value-param={@identifier.id}
    >
      <.identifier_content has_cover?={@has_cover?} identifier={@identifier}>
        <:delete>
          <%= render_slot(@delete) %>
        </:delete>
        <%= render_slot(@inner_block) %>
      </.identifier_content>
    </article>
    """
  end

  attr :assoc_identifier, :any
  attr :identifier, :any
  attr :assoc_identifiers, :list, default: nil
  attr :identifier_id, :integer
  attr :available_identifiers, :list, default: []
  attr :select, :any, default: false
  slot :inner_block, default: nil
  slot :delete

  # shown as selected
  def assoc_identifier(%{assoc_identifier: assoc_identifier} = assigns) do
    changeset = assoc_identifier.source
    identifier_changeset = Changeset.get_assoc(changeset, :identifier)

    identifier =
      if identifier_changeset == nil do
        identifier_id = Changeset.get_field(changeset, :identifier_id)
        Enum.find(assigns.available_identifiers, &(&1.id == identifier_id))
      else
        identifier_changeset.data
      end

    assigns =
      assigns
      |> assign(:identifier, identifier)
      |> assign(:has_cover?, Map.has_key?(identifier, :cover))

    ~H"""
    <article
      data-id={@identifier.id}
      class={[
        "draggable",
        "identifier"
      ]}
      phx-page-loading
      phx-click={@select}
      phx-value-param={@identifier.id}
    >
      <Input.hidden field={@assoc_identifier[:parent_id]} />
      <Input.hidden field={@assoc_identifier[:identifier_id]} />

      <.identifier_content has_cover?={@has_cover?} identifier={@identifier}>
        <:delete>
          <%= render_slot(@delete) %>
        </:delete>
        <%= render_slot(@inner_block) %>
      </.identifier_content>
    </article>
    """
  end

  def assoc_identifier(%{identifier: identifier, assoc_identifiers: assoc_identifiers} = assigns)
      when not is_nil(assoc_identifiers) do
    assoc_identifiers_changesets =
      Changeset.get_assoc(assoc_identifiers.form.source, assoc_identifiers.field)

    selected =
      Enum.find(
        assoc_identifiers_changesets,
        &(Changeset.get_field(&1, :identifier_id) == identifier.id)
      )

    assigns =
      assigns
      |> assign(:identifier, identifier)
      |> assign(:has_cover?, Map.has_key?(identifier, :cover))
      |> assign(:selected, selected && selected.action != :replace)

    ~H"""
    <article
      data-id={@identifier.id}
      class={[
        "identifier",
        @selected && "selected"
      ]}
      phx-page-loading
      phx-click={@select}
      phx-value-param={@identifier.id}
    >
      <.identifier_content has_cover?={@has_cover?} identifier={@identifier}>
        <:delete>
          <%= render_slot(@delete) %>
        </:delete>
        <%= render_slot(@inner_block) %>
      </.identifier_content>
    </article>
    """
  end

  @doc """
  Dumb identifier is used to display identifiers we've made on the fly, instead of
  referencing identifiers stored in the database.
  """
  attr :identifier, :map, required: true
  attr :select, :any, default: false
  slot :delete

  def dumb_identifier(%{identifier: identifier} = assigns) when not is_nil(identifier) do
    assigns =
      assigns
      |> assign(:identifier, identifier)
      |> assign(:has_cover?, Map.has_key?(identifier, :cover))

    ~H"""
    <article
      data-id={@identifier.entry_id}
      class={[
        "draggable",
        "identifier",
        @select && "selectable"
      ]}
      phx-page-loading
      phx-click={@select}
    >
      <.identifier_content has_cover?={@has_cover?} identifier={@identifier}>
        <:delete>
          <%= render_slot(@delete) %>
        </:delete>
        <%= render_slot(@inner_block) %>
      </.identifier_content>
    </article>
    """
  end

  attr :identifier, :map, required: true
  attr :has_cover?, :boolean, default: false
  slot :delete
  slot :inner_block

  def identifier_content(assigns) do
    identifier = assigns.identifier
    schema = identifier.schema

    translated_type =
      Utils.try_path(schema.__translations__(), [:naming, :singular]) ||
        schema.__naming__().singular

    assigns = assign(assigns, :type, String.upcase(translated_type))

    ~H"""
    <section class="cover-wrapper">
      <div class="cover">
        <img src={(@has_cover? && @identifier.cover) || "/images/admin/avatar.svg"} />
      </div>
    </section>
    <section class="content">
      <%= render_slot(@inner_block) %>
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
          <span>|</span> <%= format_datetime(@identifier.updated_at) %>
        </div>
      </div>
    </section>
    <div class="remove">
      <%= render_slot(@delete) %>
    </div>
    """
  end

  defp get_list_opts(schema_module, available_schemas) do
    Enum.find(available_schemas, &(elem(&1, 1) == schema_module))
  end

  def insert_identifier(assoc_identifiers, identifier_id, assoc_schema) do
    new_assoc_identifier =
      assoc_schema
      |> struct(%{})
      |> Changeset.change()
      |> Changeset.put_change(:identifier_id, identifier_id)
      |> Map.put(:action, :insert)

    (assoc_identifiers ++ [new_assoc_identifier]) |> dbg
  end

  def remove_identifier(assoc_identifiers, identifier_id) do
    Enum.reject(
      assoc_identifiers,
      &(Changeset.get_field(&1, :identifier_id) == identifier_id)
    )
  end
end
