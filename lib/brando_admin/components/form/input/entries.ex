defmodule BrandoAdmin.Components.Form.Input.Entries do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.Authorization.Boundary
  alias Brando.Blueprint.Identifier
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Content.Identifier, as: IdentifierRow
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.SubformHelpers
  alias BrandoAdmin.Components.Form.Primitives
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

    %{opts: %{module: join_schema} = field_opts} =
      Brando.Blueprint.Relations.__relation__(schema, field.field)

    wanted_schemas = Keyword.get(assigns.opts, :sources)

    if !wanted_schemas do
      raise Brando.Exception.BlueprintError,
        message: """
        Missing `sources` option for `:entries` field `#{inspect(field.field)}`

            input :#{inspect(field.field)}, :entries, sources: [
              {MyApp.Projects.Project, %{order: "asc title"}},
              {Brando.Pages.Page, %{}}
            ]

        """
    end

    # Count active (non-dropped) entries from the changeset
    active_count =
      field.form.source
      |> Ecto.Changeset.get_assoc(field.field)
      |> Enum.reject(&(&1.action == :replace))
      |> length()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:has_entries, active_count > 0)
     |> prepare_input_component()
     |> assign_new(:join_schema, fn -> join_schema end)
     |> assign_new(:max_length, fn -> get_in(field_opts, [:constraints, :max_length]) end)
     |> assign_new(:min_length, fn -> get_in(field_opts, [:constraints, :min_length]) end)
     |> assign_available_schemas(wanted_schemas)
     |> assign_new(:selected_schema, fn %{available_schemas: schemas} -> single_schema(schemas) end)
     |> assign_new(:available_identifiers, fn -> [] end)
     |> keep_filters(wanted_schemas)
     |> assign_selected_identifiers(field)}
  end

  # What the lists read here depend on: the keys the authorization hook
  # loaded for this event grants (`Boundary.presentation/0`, nil without
  # group authorization) and `Boundary.read_generation/0`, which a change of
  # permissions and a form reading its entry again raise: a record read
  # policy can decide otherwise with the same grants. The keys alone: the
  # groups that give them come in no set order, and may be renamed.
  defp read_key do
    grants =
      case Boundary.presentation() do
        %{grants: grants, superuser?: superuser?} -> {grants |> Map.keys() |> Enum.sort(), superuser?}
        _ -> nil
      end

    {Boundary.read_generation(), grants}
  end

  # The selected entries the editor may read, in the order of the rows, as
  # the changeset preloaded them, or else as last read: a row added since
  # (picked, synced from another editor, recovered) is read by id. The
  # preload has no read policy applied, so each row is named only if
  # `Boundary.readable_entries/1` allows it, and is otherwise left out of the
  # list and shown masked. A decision is kept with the identifier it was made
  # on (`identifier_decisions`) while `read_key/0` stays the same, so a
  # render checks only rows it has not seen, and a row whose identifier
  # changed again. The picker's entries come through `Boundary.identifiers/1`
  # and are readable.
  defp assign_selected_identifiers(socket, field) do
    associations = Changeset.get_assoc(field.form.source, field.field) |> Enum.reject(&(&1.action == :replace))
    ids = Enum.map(associations, &Changeset.get_field(&1, :identifier_id)) |> Enum.reject(&is_nil/1)
    key = read_key()
    fresh? = Map.has_key?(socket.assigns, :selected_read_key) and socket.assigns.selected_read_key == key
    decisions = if fresh?, do: socket.assigns.identifier_decisions, else: %{}
    decisions = Map.take(decisions, ids)

    decisions =
      for %{id: id} = identifier <- List.wrap(socket.assigns[:available_identifiers]),
          id in ids and not Map.has_key?(decisions, id),
          into: decisions,
          do: {id, {identifier, true}}

    preloaded =
      for association <- associations,
          %{id: id, schema: _, entry_id: _} = identifier <- [loaded_identifier(association)],
          id in ids,
          into: %{},
          do: {id, identifier}

    decided = Map.new(decisions, fn {id, {identifier, _}} -> {id, identifier} end)
    unread = Enum.reject(ids, &(Map.has_key?(preloaded, &1) or Map.has_key?(decided, &1)))
    current = decided |> Map.merge(read_identifiers(unread)) |> Map.merge(preloaded)
    undecided = Enum.filter(ids, &(not Map.has_key?(decisions, &1) or elem(decisions[&1], 0) != current[&1]))
    checked = for id <- undecided, identifier = current[id], do: identifier
    readable = Boundary.readable_entries(Enum.map(checked, &{&1.schema, &1.entry_id}))

    decisions =
      Enum.reduce(undecided, decisions, fn id, acc ->
        identifier = current[id]
        Map.put(acc, id, {identifier, identifier != nil and {identifier.schema, identifier.entry_id} in readable})
      end)

    selected =
      Enum.map(ids, fn id ->
        case decisions[id] do
          {identifier, true} -> identifier
          _ -> nil
        end
      end)

    socket
    |> assign(:selected_read_key, key)
    |> assign(:identifier_decisions, decisions)
    |> assign(:selected_identifiers, Enum.filter(selected, & &1))
    |> assign(:selected_text, Enum.map_join(selected, ", ", &((&1 && &1.title) || IdentifierRow.masked_label())))
  end

  # The row's identifier, unless the query that read the row left it out
  # (a project's own query for a subform's rows may): the row is then read
  # by id
  defp loaded_identifier(%Changeset{data: %{identifier: %Ecto.Association.NotLoaded{}}, changes: changes})
       when not is_map_key(changes, :identifier),
       do: nil

  defp loaded_identifier(row), do: Changeset.get_field(row, :identifier)

  # By id, for `assign_selected_identifiers/2` to decide what may be named
  defp read_identifiers([]), do: %{}

  defp read_identifiers(ids) do
    import Ecto.Query, only: [from: 2]
    from(i in Brando.Content.Identifier, where: i.id in ^ids) |> Brando.Repo.all() |> Map.new(&{&1.id, &1})
  end

  # What the picker's list depends on
  defp filters_key(socket, wanted_schemas) do
    filter_language? = Keyword.get(socket.assigns.opts, :filter_language, false)
    language = if filter_language?, do: socket.assigns.field.form[:language].value
    {wanted_schemas, filter_language?, language, read_key()}
  end

  # The picker's list is read when the picker opens and before a pick is
  # taken from it, and again only if what it depends on changed since.
  # Not on a render: a save, a change of permissions or another editor's
  # save would read it for every entries input, in every subform row.
  defp refresh_filters(socket, wanted_schemas) do
    key = filters_key(socket, wanted_schemas)

    if socket.assigns[:identifier_filters] == key do
      socket
    else
      socket
      |> assign(:identifier_filters, key)
      |> assign_available_schemas(wanted_schemas)
      |> assign_selected_schema()
    end
  end

  # On a render, a list read before what it depends on changed is read
  # again while the picker is open, and dropped while it is closed, so it
  # names nothing the editor may no longer read. It is read when the picker
  # opens.
  defp keep_filters(socket, wanted_schemas) do
    cond do
      socket.assigns[:identifier_filters] in [nil, filters_key(socket, wanted_schemas)] -> socket
      socket.assigns[:picker_open?] -> refresh_filters(socket, wanted_schemas)
      true -> assign(socket, identifier_filters: nil, available_identifiers: [])
    end
  end

  def assign_available_schemas(socket, wanted_schemas) do
    assign(socket, :available_schemas, Identifier.get_entry_types(wanted_schemas))
  end

  # The content type the picker opens on when it offers only one
  defp single_schema([{_, schema, _}]), do: schema
  defp single_schema(_schemas), do: nil

  def assign_selected_schema(socket) do
    schemas = socket.assigns.available_schemas
    current = socket.assigns[:selected_schema]
    selected = Enum.find(schemas, &(elem(&1, 1) == current)) || if(length(schemas) == 1, do: hd(schemas))

    {schema, identifiers} =
      if selected do
        {_, schema, list_opts} = selected
        list_opts = maybe_filter_by_language(list_opts, socket.assigns.opts, socket)
        {:ok, identifiers} = Identifier.list_entries_for(schema, list_opts)
        {schema, identifiers}
      else
        {nil, []}
      end

    socket
    |> assign(:selected_schema, schema)
    |> assign(:available_identifiers, identifiers)
  end

  defp maybe_filter_by_language(list_opts, field_opts, socket) do
    language = socket.assigns.field.form[:language].value

    if Keyword.get(field_opts, :filter_language, false) and language not in [nil, ""] do
      Map.put(list_opts, :language, language)
    else
      list_opts
    end
  end

  defp restore_replaced_identifier(assoc_identifiers, replaced_changeset, identifier_id) do
    Enum.map(assoc_identifiers, fn assoc_identifier ->
      if Changeset.get_field(assoc_identifier, :identifier_id) == identifier_id do
        action = (Changeset.get_field(assoc_identifier, :id) == nil && :insert) || nil
        Map.put(replaced_changeset, :action, action)
      else
        assoc_identifier
      end
    end)
  end

  def render(assigns) do
    ~H"""
    <div>
      <Primitives.field_base
        field={@field}
        label={@label}
        instructions={@instructions}
        class={@class}
        compact={@compact}
        locked={@locked}
      >
        <:value>
          <%= if @has_entries do %>
            {@selected_text}
          <% else %>
            {gettext("No selected entries")}
          <% end %>
        </:value>
        <div class="entries-input identifier-field">
          <div
            id={"#{@field.id}-selected-identifiers"}
            class="identifier-field-copy"
            phx-hook="Brando.TableRows"
            data-row-selector=".identifier-list > .identifier"
          >
            <%= if !@has_entries do %>
              <div class="identifier-empty">
                <span class="identifier-empty-icon" aria-hidden="true"><.icon name="link" /></span>
                <span>{gettext("No selected entries")}</span>
                <input type="hidden" name={"#{@field.form.name}[drop_#{@field.field}_ids][]"} />
              </div>
            <% else %>
              <div
                id={"sortable-#{@field.id}-identifiers"}
                class="selected-entries identifier-list"
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
                  <.assoc_identifier assoc_identifier={identifier_form} available_identifiers={@selected_identifiers}>
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
                        aria-label={gettext("Remove")}
                        phx-click={JS.dispatch("change")}
                      >
                        <.icon name="x" />
                      </button>
                    </:delete>
                  </.assoc_identifier>
                </.inputs_for>
                <input type="hidden" name={"#{@field.form.name}[drop_#{@field.field}_ids][]"} />
              </div>
            <% end %>
          </div>
          <div class="identifier-actions">
            <div class="media-field-split">
              <button
                type="button"
                class="media-button"
                phx-click={JS.push("open_picker", target: @myself) |> show_modal("##{@field.id}-select-entries")}
              >
                {gettext("Select entries")}
              </button>
              <button type="button" class="media-button" phx-click="clear_all" phx-target={@myself} disabled={!@has_entries}>
                {gettext("Clear all")}
              </button>
            </div>
          </div>
        </div>

        <Content.modal
          title={gettext("Select entries")}
          id={"#{@field.id}-select-entries"}
          close={JS.push("close_picker", target: @myself) |> hide_modal("##{@field.id}-select-entries")}
          narrow
        >
          <h2 :if={!@selected_schema} class="titlecase">{gettext("Select content type")}</h2>
          <div :if={!@selected_schema} class="button-group-vertical">
            <button
              :for={{label, schema, _} <- @available_schemas}
              :key={schema}
              type="button"
              class="btn"
              phx-click={JS.push("select_schema", target: @myself)}
              phx-value-schema={schema}
            >
              {label}
            </button>
          </div>
          <%= if @selected_schema do %>
            <.entry_picker id={"#{@field.id}-entries"}>
              <.assoc_identifier
                :for={identifier <- @available_identifiers}
                identifier={identifier}
                select={JS.push("select_identifier", value: %{id: identifier.id}, target: @myself)}
                available_identifiers={@available_identifiers}
                assoc_identifiers={@field}
              />
            </.entry_picker>
          <% end %>
        </Content.modal>
      </Primitives.field_base>
    </div>
    """
  end

  attr :id, :string, required: true
  slot :inner_block, required: true

  def entry_picker(assigns) do
    ~H"""
    <div id={@id} phx-hook="Brando.SelectFilter" data-target=".identifier" data-filter-target={"##{@id}-options"}>
      <div class="select-filter entry-picker-filter">
        <div class="field-wrapper">
          <div class="label-wrapper">
            <label for={"#{@id}-search"} class="control-label">{gettext("Filter entries")}</label>
          </div>
          <%!-- This query is client-owned and must survive selection patches. --%>
          <div id={"#{@id}-search-control"} class="field-base filter-input-wrapper" phx-update="ignore">
            <.icon name="search" class="filter-icon" />
            <input
              id={"#{@id}-search"}
              type="search"
              class="text"
              placeholder={gettext("Filter entries…")}
              autocomplete="off"
            />
            <button type="button" class="filter-clear" aria-label={gettext("Clear filter")}>
              <.icon name="x" />
            </button>
          </div>
        </div>
      </div>
      <h2 class="titlecase">{gettext("Available entries")}</h2>
      <div id={"#{@id}-options"} class="entry-picker-options identifier-list">
        <div class="no-results" role="status">{gettext("No matching entries")}</div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  def handle_event("clear_all", _, socket) do
    field = socket.assigns.field
    put_changeset(socket, Changeset.put_assoc(field.form.source, field.field, []))
    {:noreply, socket}
  end

  def handle_event("open_picker", _, socket) do
    {:noreply, socket |> assign(:picker_open?, true) |> refresh_filters(Keyword.get(socket.assigns.opts, :sources))}
  end

  def handle_event("close_picker", _, socket), do: {:noreply, assign(socket, :picker_open?, false)}

  # Only an entry the picker lists: it may have reloaded since it showed one,
  # and lists again here if what the editor may read can have changed since
  # (`read_key/0`)
  def handle_event("select_identifier", %{"id" => identifier_id}, socket) do
    socket = refresh_filters(socket, Keyword.get(socket.assigns.opts, :sources))

    if Enum.any?(socket.assigns.available_identifiers, &(to_string(&1.id) == to_string(identifier_id))),
      do: select_identifier(socket, identifier_id),
      else: {:noreply, socket}
  end

  def handle_event("select_schema", %{"schema" => schema}, %{assigns: %{available_schemas: available_schemas}} = socket) do
    case Enum.find(available_schemas, &(to_string(elem(&1, 1)) == schema)) do
      nil ->
        {:noreply, socket}

      {_, schema_module, list_opts} ->
        list_opts = maybe_filter_by_language(list_opts, socket.assigns.opts, socket)
        {:ok, identifiers} = Identifier.list_entries_for(schema_module, list_opts)

        {:noreply,
         socket
         |> assign(:identifier_filters, filters_key(socket, Keyword.get(socket.assigns.opts, :sources)))
         |> assign(:available_identifiers, identifiers)
         |> assign(:selected_schema, schema_module)}
    end
  end

  defp select_identifier(socket, identifier_id) do
    identifiers_field = socket.assigns.field
    field_name = identifiers_field.field
    form = identifiers_field.form
    changeset = form.source
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
          restore_replaced_identifier(assoc_identifiers, replaced_changeset, identifier_id)

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

      put_changeset(socket, updated_changeset)

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

  # The input's changeset, to the component that owns it: a subform row's
  # to its subform, which puts the row in the form's latest list
  # (`Subform.update/2`), the entry's own to the form. The changeset of a
  # row names the row's schema, not the form.
  defp put_changeset(%{assigns: %{subform_id: subform_id}} = socket, changeset) when not is_nil(subform_id) do
    send_update(BrandoAdmin.Components.Form.Subform,
      id: subform_id,
      key: SubformHelpers.row_key(socket.assigns.field.form),
      action: :update_changeset,
      updated_changeset: changeset
    )
  end

  defp put_changeset(_socket, changeset) do
    module = changeset.data.__struct__

    send_update(BrandoAdmin.Components.Form,
      id: "#{module.__naming__().singular}_form",
      action: :update_changeset,
      changeset: changeset
    )
  end

  attr :block_identifier, :any
  attr :draggable, :boolean, default: true
  attr :identifier, :any
  attr :block_identifiers, :list, default: nil
  attr :identifier_id, :integer
  attr :available_identifiers, :list, default: []
  attr :select, :any, default: false
  slot :inner_block
  slot :delete
  slot :meta

  def block_identifier(%{block_identifier: block_identifier} = assigns) do
    changeset = block_identifier.source
    identifier_id = Changeset.get_field(changeset, :identifier_id)

    # The loaded identifier only while the row still points at it: a
    # synchronized translation or a restored copy changes the id alone.
    identifier =
      case changeset.data.identifier do
        %Brando.Content.Identifier{id: ^identifier_id} = identifier -> identifier
        _ -> Enum.find(assigns.available_identifiers, &(&1.id == identifier_id))
      end

    assigns =
      assigns
      |> assign(:identifier, identifier)
      |> assign(:has_cover?, identifier && Map.has_key?(identifier, :cover))

    ~H"""
    <article
      :if={@identifier}
      data-id={@identifier.id}
      data-label={Brando.Content.Identifier.title_text(@identifier)}
      class={[
        @draggable && "draggable",
        "identifier"
      ]}
      phx-click={@select}
      phx-value-param={@identifier.id}
    >
      <Input.hidden field={@block_identifier[:id]} />
      <Input.hidden field={@block_identifier[:block_id]} />
      <Input.hidden field={@block_identifier[:identifier_id]} />

      <.identifier_content draggable={@draggable} has_cover?={@has_cover?} identifier={@identifier}>
        <:delete>
          {render_slot(@delete)}
        </:delete>
        {render_slot(@inner_block)}
      </.identifier_content>
      <div :if={@meta != []} class="meta" data-sortable-filter>
        {render_slot(@meta, @identifier)}
      </div>
    </article>
    <%!-- Not found: the row keeps its values, so a save can't blank its id. --%>
    <div :if={!@identifier} hidden>
      <Input.hidden field={@block_identifier[:id]} />
      <Input.hidden field={@block_identifier[:block_id]} />
      <Input.hidden field={@block_identifier[:identifier_id]} />
    </div>
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
      |> assign(:selected, selected != nil && selected.action != :replace)

    ~H"""
    <button
      type="button"
      aria-pressed={to_string(@selected)}
      data-id={@identifier.id}
      data-label={Brando.Content.Identifier.title_text(@identifier)}
      class={[
        "identifier",
        "selectable",
        @selected && "selected"
      ]}
      phx-click={@select}
      phx-value-param={@identifier.id}
    >
      <.identifier_content selectable selected={@selected} has_cover?={@has_cover?} identifier={@identifier}>
        <:delete>
          {render_slot(@delete)}
        </:delete>
        {render_slot(@inner_block)}
      </.identifier_content>
    </button>
    """
  end

  attr :identifier_id, :integer
  attr :available_identifiers, :list, default: []
  attr :selected_identifiers, :list, default: []
  attr :select, :any, default: false
  slot :inner_block
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
      data-label={Brando.Content.Identifier.title_text(@identifier)}
      class={[
        "identifier",
        @select && "selectable",
        @identifier in @selected_identifiers && "selected"
      ]}
      phx-click={@select}
      phx-value-param={@identifier.id}
    >
      <.identifier_content
        selectable={!!@select}
        selected={@identifier in @selected_identifiers}
        has_cover?={@has_cover?}
        identifier={@identifier}
      >
        <:delete>
          {render_slot(@delete)}
        </:delete>
        {render_slot(@inner_block)}
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
  slot :inner_block
  slot :delete

  # shown as selected: named from `available_identifiers`, the selected
  # entries the editor may read, never from the row's preloaded identifier.
  # Any other row is masked, and keeps its inputs, so a save keeps the link
  # and the editor may still move or remove it.
  def assoc_identifier(%{assoc_identifier: assoc_identifier} = assigns) do
    identifier_id = Changeset.get_field(assoc_identifier.source, :identifier_id)
    identifier = Enum.find(assigns.available_identifiers, &(&1.id == identifier_id))

    assigns =
      assigns
      |> assign(:identifier, identifier)
      |> assign(:has_cover?, identifier && Map.has_key?(identifier, :cover))

    ~H"""
    <article
      data-id={@identifier && @identifier.id}
      data-label={if @identifier, do: Brando.Content.Identifier.title_text(@identifier), else: IdentifierRow.masked_label()}
      class={[
        "draggable",
        "identifier",
        !@identifier && "masked"
      ]}
      phx-click={@identifier && @select}
      phx-value-param={@identifier && @identifier.id}
    >
      <Input.hidden field={@assoc_identifier[:parent_id]} />
      <Input.hidden field={@assoc_identifier[:identifier_id]} />

      <%= if @identifier do %>
        <.identifier_content draggable has_cover?={@has_cover?} identifier={@identifier}>
          <:delete>
            {render_slot(@delete)}
          </:delete>
          {render_slot(@inner_block)}
        </.identifier_content>
      <% else %>
        <IdentifierRow.masked draggable>
          <:delete>
            {render_slot(@delete)}
          </:delete>
        </IdentifierRow.masked>
      <% end %>
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
      |> assign(:selected, selected != nil && selected.action != :replace)

    ~H"""
    <button
      type="button"
      aria-pressed={to_string(@selected)}
      data-id={@identifier.id}
      data-label={Brando.Content.Identifier.title_text(@identifier)}
      class={[
        "identifier",
        "selectable",
        @selected && "selected"
      ]}
      phx-click={@select}
      phx-value-param={@identifier.id}
    >
      <.identifier_content selectable selected={@selected} has_cover?={@has_cover?} identifier={@identifier}>
        <:delete>
          {render_slot(@delete)}
        </:delete>
        {render_slot(@inner_block)}
      </.identifier_content>
    </button>
    """
  end

  @doc """
  Dumb identifier is used to display identifiers we've made on the fly, instead of
  referencing identifiers stored in the database.
  """
  attr :identifier, :map, required: true
  attr :select, :any, default: false
  slot :delete
  slot :inner_block

  def dumb_identifier(%{identifier: identifier} = assigns) when not is_nil(identifier) do
    assigns =
      assigns
      |> assign(:identifier, identifier)
      |> assign(:has_cover?, Map.has_key?(identifier, :cover))

    ~H"""
    <article
      data-id={@identifier.entry_id}
      class={[
        "identifier",
        @select && "selectable"
      ]}
      phx-click={@select}
    >
      <.identifier_content has_cover?={@has_cover?} identifier={@identifier}>
        <:delete :if={@delete != []}>
          {render_slot(@delete)}
        </:delete>
        {render_slot(@inner_block)}
      </.identifier_content>
    </article>
    """
  end

  attr :identifier, :map, required: true
  attr :has_cover?, :boolean, default: false
  attr :draggable, :boolean, default: false
  attr :selectable, :boolean, default: false
  attr :selected, :boolean, default: false
  slot :delete
  slot :inner_block

  def identifier_content(assigns) do
    ~H"""
    <IdentifierRow.content identifier={@identifier} draggable={@draggable} selectable={@selectable} selected={@selected}>
      <:delete :if={@delete != []}>{render_slot(@delete)}</:delete>
      {render_slot(@inner_block)}
    </IdentifierRow.content>
    """
  end

  def insert_identifier(assoc_identifiers, identifier_id, assoc_schema) do
    new_assoc_identifier =
      assoc_schema
      |> struct(%{})
      |> Changeset.change()
      |> Changeset.put_change(:identifier_id, identifier_id)
      |> Map.put(:action, :insert)

    assoc_identifiers ++ [new_assoc_identifier]
  end

  def remove_identifier(assoc_identifiers, identifier_id) do
    Enum.reject(
      assoc_identifiers,
      &(Changeset.get_field(&1, :identifier_id) == identifier_id)
    )
  end
end
