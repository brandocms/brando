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
    join_field_name = :"#{assigns.field.field}_identifiers"
    join_field = assigns.field.form[join_field_name]

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

    delete_field_name =
      String.replace(
        assigns.field.name,
        "#{assigns.field.field}",
        "#{assigns.field.field}_delete"
      ) <>
        "[]"

    sort_field_name =
      String.replace(
        assigns.field.name,
        "#{assigns.field.field}",
        "#{assigns.field.field}_sequence"
      ) <>
        "[]"

    {:ok,
     socket
     |> assign(assigns)
     |> prepare_input_component()
     |> assign_new(:selected_schema, fn -> nil end)
     |> assign(:identifiers_field, join_field)
     |> assign(:join_field_name, join_field_name)
     |> assign_new(:selected_identifiers, fn -> Enum.map(join_field.value, & &1.identifier) end)
     |> assign_new(:identifiers, fn %{selected_identifiers: ids} -> ids end)
     |> assign(:delete_field_name, delete_field_name)
     |> assign(:sort_field_name, sort_field_name)
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
        field={@identifiers_field}
        label={@label}
        instructions={@instructions}
        class={@class}
        compact={@compact}
      >
        <input type="hidden" name={@delete_field_name} />

        <%= if Enum.empty?(@selected_identifiers) do %>
          <div class="empty-list">
            <%= gettext("No selected entries") %>
          </div>
        <% else %>
          <div
            id={"sortable-#{@field.id}-identifiers"}
            class="selected-entries"
            phx-hook="Brando.SortableInputsFor"
            data-target={@myself}
            data-sortable-id={"sortable-#{@field.id}-identifiers"}
            data-sortable-handle=".sort-handle"
            data-sortable-selector=".identifier"
          >
            <.inputs_for :let={identifier_form} field={@identifiers_field}>
              <Input.input type={:hidden} field={identifier_form[:identifier_id]} />
              <.identifier
                identifier_id={identifier_form[:identifier_id].value}
                available_identifiers={@identifiers}
                sortable
              >
                <:delete>
                  <input type="hidden" name={@sort_field_name} value={identifier_form.index} />
                  <label>
                    <input
                      type="checkbox"
                      name={@delete_field_name}
                      value={identifier_form.index}
                      class="hidden"
                    />
                    <.icon name="hero-x-mark" />
                  </label>
                </:delete>
              </.identifier>
            </.inputs_for>
          </div>
        <% end %>

        <button
          type="button"
          class="add-entry-button"
          phx-click={show_modal("##{@field.id}-select-entries")}
        >
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16">
            <path fill="none" d="M0 0h24v24H0z" /><path
              d="M18 15l-.001 3H21v2h-3.001L18 23h-2l-.001-3H13v-2h2.999L16 15h2zm-7 3v2H3v-2h8zm10-7v2H3v-2h18zm0-7v2H3V4h18z"
              fill="rgba(252,245,243,1)"
            />
          </svg>
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
            <.identifier
              :for={identifier <- @identifiers}
              identifier_id={identifier.id}
              select={JS.push("select_identifier", target: @myself, value: %{id: identifier.id})}
              selected_identifiers={@selected_identifiers}
              available_identifiers={@identifiers}
            />
          <% end %>
        </Content.modal>
      </Form.field_base>
    </div>
    """
  end

  def handle_event(
        "select_identifier",
        %{"id" => identifier_id},
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
    selected_identifier = Enum.find(identifiers, &(to_string(&1.id) == to_string(identifier_id)))

    updated_identifiers =
      case Enum.find(selected_identifiers, &(&1 == selected_identifier)) do
        nil -> selected_identifiers ++ List.wrap(selected_identifier)
        _ -> Enum.reject(selected_identifiers, &(&1 == selected_identifier))
      end

    built_join_entries =
      Enum.map(updated_identifiers, fn identifier ->
        %{}
        |> Map.put(:identifier_id, identifier.id)
        |> Map.put(:sequence, Enum.count(updated_identifiers))
      end)

    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    updated_changeset =
      Changeset.put_assoc(changeset, :"#{field_name}_identifiers", built_join_entries)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, assign(socket, :selected_identifiers, updated_identifiers)}
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
     |> assign(:identifiers, identifiers)
     |> assign(:selected_schema, schema_module)}
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

  attr :block_identifier, :any
  attr :identifier, :any
  attr :block_identifiers, :list, default: nil
  attr :identifier_id, :integer
  attr :available_identifiers, :list, default: []
  attr :select, :any, default: false
  attr :sortable, :boolean, default: false
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
        "draggable",
        "identifier"
      ]}
      phx-page-loading
      phx-click={@select}
      phx-value-param={@identifier.id}
    >
      <Input.hidden field={@block_identifier[:block_id]} />
      <Input.hidden field={@block_identifier[:identifier_id]} />

      <%= render_slot(@inner_block) %>

      <%= if @sortable do %>
        <section class="sort-handle">
          <svg
            width="15"
            height="15"
            viewBox="0 0 15 15"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
          >
            <circle cx="1.5" cy="1.5" r="1.5"></circle>
            <circle cx="7.5" cy="1.5" r="1.5"></circle>
            <circle cx="13.5" cy="1.5" r="1.5"></circle>
            <circle cx="1.5" cy="7.5" r="1.5"></circle>
            <circle cx="7.5" cy="7.5" r="1.5"></circle>
            <circle cx="13.5" cy="7.5" r="1.5"></circle>
            <circle cx="1.5" cy="13.5" r="1.5"></circle>
            <circle cx="7.5" cy="13.5" r="1.5"></circle>
            <circle cx="13.5" cy="13.5" r="1.5"></circle>
          </svg>
        </section>
      <% end %>
      <section class="cover-wrapper">
        <div class="cover">
          <img src={(@has_cover? && @identifier.cover) || "/images/admin/avatar.svg"} />
        </div>
      </section>
      <section class="content">
        <div class="info">
          <div class="name">
            <%= @identifier.title %>
          </div>
          <div class="meta-info">
            <Row.status_circle status={@identifier.status} /> <%= @type %>#<%= Brando.HTML.zero_pad(
              @identifier.entry_id
            ) %>
            <span>|</span> <%= format_datetime(@identifier.updated_at) %> [iid:<%= @identifier.id %>]
          </div>
        </div>
      </section>
      <div class="remove">
        <%= render_slot(@delete) %>
      </div>
    </article>
    """
  end

  def block_identifier(%{identifier: identifier, block_identifiers: block_identifiers} = assigns)
      when not is_nil(block_identifiers) do
    schema = identifier.schema

    translated_type =
      Utils.try_path(schema.__translations__(), [:naming, :singular]) ||
        schema.__naming__().singular

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
      |> assign(:type, String.upcase(translated_type))
      |> assign(:selected, selected && selected.action != :replace)

    ~H"""
    <article
      data-id={@identifier.id}
      class={[
        "draggable",
        "identifier",
        @selected && "selected"
      ]}
      phx-page-loading
      phx-click={@select}
      phx-value-param={@identifier.id}
    >
      <%= render_slot(@inner_block) %>

      <section class="cover-wrapper">
        <div class="cover">
          <img src={(@has_cover? && @identifier.cover) || "/images/admin/avatar.svg"} />
        </div>
      </section>
      <section class="content">
        <div class="info">
          <div class="name">
            <%= @identifier.title %>
          </div>
          <div class="meta-info">
            <Row.status_circle status={@identifier.status} /> <%= @type %>#<%= Brando.HTML.zero_pad(
              @identifier.entry_id
            ) %>
            <span>|</span> <%= format_datetime(@identifier.updated_at) %> [iid:<%= @identifier.id %>]
          </div>
        </div>
        <div class="icon">
          <.icon name="hero-check-circle" />
        </div>
      </section>
      <div class="remove">
        <%= render_slot(@delete) %>
      </div>
    </article>
    """
  end

  attr :identifier_id, :integer
  attr :available_identifiers, :list, default: []
  attr :selected_identifiers, :list, default: []
  attr :select, :any, default: false
  attr :sortable, :boolean, default: false
  slot :delete

  def identifier(%{identifier_id: identifier_id} = assigns) when not is_nil(identifier_id) do
    available_identifiers = assigns.available_identifiers

    identifier =
      Enum.find(
        available_identifiers,
        &(to_string(&1.id) == to_string(identifier_id))
      )

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
        "draggable",
        "identifier",
        @select && "selectable",
        @identifier in @selected_identifiers && "selected"
      ]}
      phx-page-loading
      phx-click={@select}
      phx-value-param={@identifier.id}
    >
      <%= if @sortable do %>
        <section class="sort-handle">
          <svg
            width="15"
            height="15"
            viewBox="0 0 15 15"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
          >
            <circle cx="1.5" cy="1.5" r="1.5"></circle>
            <circle cx="7.5" cy="1.5" r="1.5"></circle>
            <circle cx="13.5" cy="1.5" r="1.5"></circle>
            <circle cx="1.5" cy="7.5" r="1.5"></circle>
            <circle cx="7.5" cy="7.5" r="1.5"></circle>
            <circle cx="13.5" cy="7.5" r="1.5"></circle>
            <circle cx="1.5" cy="13.5" r="1.5"></circle>
            <circle cx="7.5" cy="13.5" r="1.5"></circle>
            <circle cx="13.5" cy="13.5" r="1.5"></circle>
          </svg>
        </section>
      <% end %>
      <section class="cover-wrapper">
        <div class="cover">
          <img src={(@has_cover? && @identifier.cover) || "/images/admin/avatar.svg"} />
        </div>
      </section>
      <section class="content">
        <div class="info">
          <div class="name">
            <%= @identifier.title %>
          </div>
          <div class="meta-info">
            <Row.status_circle status={@identifier.status} /> <%= @type %>#<%= Brando.HTML.zero_pad(
              @identifier.entry_id
            ) %>
            <span>|</span> <%= format_datetime(@identifier.updated_at) %> [iid:<%= @identifier.id %>]
          </div>
        </div>
      </section>
      <div class="remove">
        <%= render_slot(@delete) %>
      </div>
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
      data-id={@identifier.entry_id}
      class={[
        "draggable",
        "identifier",
        @select && "selectable"
      ]}
      phx-page-loading
      phx-click={@select}
    >
      <section class="cover-wrapper">
        <div class="cover">
          <img src={(@has_cover? && @identifier.cover) || "/images/admin/avatar.svg"} />
        </div>
      </section>
      <section class="content">
        <div class="info">
          <div class="name">
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
    </article>
    """
  end

  defp get_list_opts(schema_module, available_schemas) do
    Enum.find(available_schemas, &(elem(&1, 1) == schema_module))
  end
end
