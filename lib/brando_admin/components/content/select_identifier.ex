defmodule BrandoAdmin.Components.Content.SelectIdentifier do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
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
     |> assign_new(:details, fn -> [] end)
     |> assign_new(:on_change, fn -> nil end)
     |> assign_new(:wanted_schemas, fn -> [] end)
     |> assign_new(:var_key, fn -> nil end)
     |> assign_new(:var_type, fn -> nil end)
     |> assign_new(:language, fn -> nil end)
     |> assign_new(:layout, fn -> :default end)
     |> assign_new(:statuses, fn -> nil end)
     |> sync_selection(assigns)
     |> assign_available_schemas()
     |> assign_selected_schema()}
  end

  def assign_available_schemas(socket) do
    wanted_schemas = socket.assigns.wanted_schemas

    socket = assign_new(socket, :available_schemas, fn -> schema_options(wanted_schemas) end)

    if socket.assigns.layout == :workspace do
      assign_new(socket, :schema_counts, fn ->
        import Ecto.Query, only: [from: 2]
        schemas = Enum.map(socket.assigns.available_schemas, &elem(&1, 1))

        query =
          identifier_query(schemas, socket.assigns.language, socket.assigns.statuses) |> Ecto.Query.exclude(:order_by)

        Brando.Repo.all(
          from identifier in query, group_by: identifier.schema, select: {identifier.schema, count(identifier.id)}
        )
        |> Map.new()
      end)
    else
      socket
    end
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
  def assign_selected_schema(%{assigns: %{layout: :workspace}} = socket) do
    schemas = socket.assigns.available_schemas
    current = socket.assigns.selected_identifier
    preferred = if current && Enum.any?(schemas, &(elem(&1, 1) == current.schema)), do: current.schema
    schema = preferred || (List.first(schemas) && elem(List.first(schemas), 1))

    socket
    |> assign_new(:selected_schema, fn -> schema end)
    |> assign_new(:selected_schema_raw, fn -> schema && to_string(schema) end)
    |> assign_new(:identifiers, fn ->
      if schema do
        {:ok, identifiers} = list_identifiers_for_schema(schema, socket.assigns.language, socket.assigns.statuses)
        identifiers
      else
        []
      end
    end)
  end

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
      <%= if @layout == :workspace do %>
        <div class="identifier-picker">
          <nav class="identifier-picker-nav" aria-label={gettext("Content types")}>
            <h3>{gettext("Content types")}</h3>
            <.schema_buttons
              available_schemas={@available_schemas}
              selected_schema_raw={@selected_schema_raw}
              myself={@myself}
              workspace
              schema_counts={@schema_counts}
            />
          </nav>
          <div class="identifier-picker-results">
            <.entries_list
              id={@id}
              identifiers={@identifiers}
              selected_identifier_id={@selected_identifier_id}
              myself={@myself}
              workspace
            />
          </div>
          <aside class="identifier-picker-details">
            <h3>{gettext("Selected destination")}</h3>
            <%= if @selected_identifier do %>
              <div class="identifier-destination-heading">
                <h4>{@selected_identifier.title}</h4>
                <p class="identifier-destination">{@selected_identifier.url}</p>
              </div>
              <dl class="modal-metadata">
                <div>
                  <dt>{gettext("Content type")}</dt><dd>
                    <span>{Brando.Blueprint.get_plural(@selected_identifier.schema)}</span><span
                      :if={@selected_identifier.language}
                      class="modal-badge"
                    >{String.upcase(to_string(@selected_identifier.language))}</span>
                  </dd>
                </div>
                <div>
                  <dt>{gettext("Status")}</dt><dd><.status_value status={@selected_identifier.status} /></dd>
                </div>
                <div>
                  <dt>{gettext("Last updated")}</dt><dd>
                    <span>{Brando.Utils.Datetime.format_datetime(@selected_identifier.updated_at, "%-d %B %Y · %H:%M")}</span>
                  </dd>
                </div>
              </dl>
              <Content.modal_person :if={@selected_creator} user={@selected_creator} caption={gettext("Creator")} />
            <% else %>
              <p class="modal-muted">{gettext("Select an entry to see its details.")}</p>
            <% end %>
            <div :if={@details != []} class="identifier-link-settings">{render_slot(@details)}</div>
          </aside>
        </div>
      <% else %>
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
      <% end %>
      <Input.input :if={@field} type={:hidden} field={@field} value={@selected_identifier_id} publish />
    </div>
    """
  end

  defp schema_buttons(assigns) do
    assigns = assigns |> assign_new(:workspace, fn -> false end) |> assign_new(:schema_counts, fn -> %{} end)

    ~H"""
    <div class="button-group-vertical tiny">
      <button
        :if={@workspace}
        type="button"
        class={["secondary", @selected_schema_raw == "all" && "selected"]}
        aria-pressed={to_string(@selected_schema_raw == "all")}
        phx-click={JS.push("select_schema", target: @myself)}
        phx-value-schema="all"
      >
        <.icon name="hero-squares-2x2" />
        <span class="identifier-scope-label">{gettext("All content")}</span>
        <span class="identifier-scope-count">{Enum.sum(Map.values(@schema_counts))}</span>
      </button>
      <button
        :for={{label, schema} <- @available_schemas}
        :key={schema}
        type="button"
        class={["secondary", @selected_schema_raw == to_string(schema) && "selected"]}
        aria-pressed={to_string(@selected_schema_raw == to_string(schema))}
        phx-click={JS.push("select_schema", target: @myself)}
        phx-value-schema={schema}
      >
        <.icon :if={@workspace} name={if schema == Brando.Pages.Page, do: "hero-document-text", else: "hero-folder"} />
        <span class={@workspace && "identifier-scope-label"}>{label}</span>
        <span :if={@workspace} class="identifier-scope-count">{Map.get(@schema_counts, schema, 0)}</span>
      </button>
    </div>
    """
  end

  defp entries_list(assigns) do
    assigns = assign_new(assigns, :workspace, fn -> false end)

    ~H"""
    <div
      id={"#{@id}-select-modal-filter"}
      phx-hook="Brando.SelectFilter"
      data-target=".identifier"
      data-filter-target={"##{@id}-identifier-options"}
      data-count-target={@workspace && "##{@id}-result-count"}
    >
      <h2 :if={!@workspace} class="titlecase">{gettext("Available entries")}</h2>

      <div class="select-filter">
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
                placeholder={if @workspace, do: gettext("Search by title or URL…"), else: gettext("Filter identifiers…")}
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

      <div :if={@workspace} class="identifier-results-heading">
        <span class="identifier-results-count"><span id={"#{@id}-result-count"}>{length(@identifiers)}</span> {gettext(
          "Entries"
        )}</span>
        <span>{gettext("Title")} / {gettext("URL")}</span>
      </div>
      <div id={"#{@id}-identifier-options"} class="identifier-options">
        <div class="no-results">{gettext("No matching identifiers")}</div>
        <.identifier
          :for={identifier <- @identifiers}
          :key={identifier.id}
          identifier={identifier}
          workspace={@workspace}
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
  attr :workspace, :boolean, default: false
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
      data-label={if @workspace, do: "#{@identifier.title} #{@identifier.url}", else: @identifier.title}
      aria-pressed={@select && to_string(@identifier.id == @selected_identifier_id)}
      phx-click={@select}
      phx-value-param={@identifier.id}
    >
      <%= if @workspace do %>
        <span class="identifier-result-icon"><.icon name="hero-document-text" /></span>
        <span class="identifier-result-copy"><strong>{@identifier.title}</strong><small>{@identifier.url}</small></span>
        <span class="identifier-result-meta"><span :if={@identifier.language} class="modal-badge">{String.upcase(
          to_string(@identifier.language)
        )}</span><.status_value status={@identifier.status} /></span>
        <span class="identifier-result-check"><.icon :if={@identifier.id == @selected_identifier_id} name="hero-check" /></span>
      <% else %>
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
      <% end %>
    </button>
    """
  end

  def handle_event("select_schema", %{"schema" => "all"}, %{assigns: %{layout: :workspace}} = socket) do
    schemas = Enum.map(socket.assigns.available_schemas, &elem(&1, 1))
    {:ok, identifiers} = list_identifiers_for_schema(schemas, socket.assigns.language, socket.assigns.statuses)

    {:noreply,
     socket |> assign(:identifiers, identifiers) |> assign(:selected_schema, :all) |> assign(:selected_schema_raw, "all")}
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
    |> assign(:selected_creator, selected_creator(identifier))
    |> then(&{:noreply, &1})
  end

  defp sync_selection(socket, assigns) do
    id =
      case assigns do
        %{field: %Phoenix.HTML.FormField{} = field} -> Ecto.Changeset.get_field(field.form.source, field.field)
        %{selected_identifier_id: id} -> id
        _ -> socket.assigns.selected_identifier_id
      end

    identifier = socket.assigns.selected_identifier

    if (identifier && identifier.id) != id || !Map.has_key?(socket.assigns, :selected_creator) do
      identifier = if id, do: Brando.Content.get_identifier!(id)

      socket
      |> assign(:selected_identifier_id, id)
      |> assign(:selected_identifier, identifier)
      |> assign(:selected_creator, selected_creator(identifier))
    else
      socket
    end
  end

  defp selected_creator(nil), do: nil

  defp selected_creator(%{schema: schema, entry_id: entry_id}) do
    import Ecto.Query, only: [from: 2]

    if schema.has_trait(Brando.Trait.Creator) do
      # Read only the selected entry's creator; avoid loading its blocks/assets.
      Brando.Repo.one(
        from user in Brando.Users.User,
          join: entry in ^schema,
          on: entry.creator_id == user.id,
          where: entry.id == ^entry_id,
          preload: [:avatar]
      )
    end
  end

  defp status_value(assigns) do
    ~H"""
    <span class="modal-status" data-status={@status}><Row.status_circle status={@status} /><span>{status_label(@status)}</span></span>
    """
  end

  defp status_label(:published), do: gettext("Published")
  defp status_label(:draft), do: gettext("Draft")
  defp status_label(:pending), do: gettext("Pending")
  defp status_label(:disabled), do: gettext("Disabled")
  defp status_label(:deleted), do: gettext("Deleted")
  defp status_label(_), do: gettext("Not set")

  defp list_identifiers_for_schema(schema_module, language, statuses) do
    {:ok, Brando.Repo.all(identifier_query(List.wrap(schema_module), language, statuses))}
  end

  defp identifier_query(schemas, language, statuses) do
    import Ecto.Query, only: [from: 2, where: 3]

    query =
      from(t in Brando.Content.Identifier,
        where: t.schema in ^schemas,
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

    query
  end
end
