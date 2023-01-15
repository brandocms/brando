defmodule BrandoAdmin.Components.Content.List.Row do
  use BrandoAdmin, :live_component
  use BrandoAdmin.Translator, "listings"
  import Brando.Utils.Datetime
  import Brando.Gettext

  alias BrandoAdmin.Components.Badge
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.ChildrenButton
  alias BrandoAdmin.Components.CircleDropdown
  alias BrandoAdmin.Components.Form.Input.Entries

  alias Brando.Blueprint.Listings.Template
  alias Brando.Blueprint.Identifier
  alias Brando.Trait

  # prop entry, :any
  # prop selected_rows, :list
  # prop listing, :any
  # prop schema, :any
  # prop sortable?, :boolean
  # prop status?, :boolean
  # prop creator?, :boolean
  # prop click, :event, required: true
  # prop target, :any, required: true

  def mount(socket) do
    {:ok, assign(socket, show_children: false, child_fields: [])}
  end

  def update(%{show_children: show_children, child_fields: child_fields}, socket) do
    {:ok, assign(socket, show_children: show_children, child_fields: child_fields)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:selected?, assigns.entry.id in assigns.selected_rows)
     |> assign(:singular, assigns.schema.__naming__().singular)
     |> assign(:soft_delete?, assigns.schema.has_trait(Trait.SoftDelete))}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"list-row-#{@entry.id}"}
      class={render_classes(["list-row", "draggable", selected: @selected?])}
      data-id={@entry.id}
      phx-click={@click}
      phx-value-id={@entry.id}
      phx-page-loading>
      <div class="main-content">
        <.status
          :if={@status?}
          entry={@entry}
          soft_delete?={@soft_delete?} />

        <.handle :if={@sortable?} />

        <.field
          :for={field <- @listing.fields}
          field={field}
          entry={@entry}
          schema={@schema} />

        <.alternates
          :if={@alternates?}
          entry={@entry}
          target={@myself}
          schema={@schema} />

        <.creator
          :if={@creator?}
          entry={@entry}
          soft_delete?={@soft_delete?}/>

        <.entry_menu
          schema={@schema}
          content_language={@content_language}
          entry={@entry}
          listing={@listing} />
      </div>

      <%= if @show_children do %>
        <div
          :for={child_field <- @child_fields}
          class="child-rows"
          id={"sortable-#{@entry.id}-#{child_field}"}
          data-target={@target}
          class="sort-container"
          phx-hook="Brando.Sortable"
          data-sortable-id={"child_listing|#{@entry.id}|#{child_field}"}
          data-sortable-handle=".sequence-handle"
          data-sortable-selector=".child-row">
          <.child_row
            :for={child_entry <- Map.get(@entry, child_field, [])}
            entry={child_entry}
            schema={@schema}
            target={@myself}
            content_language={@content_language}
            child_listing={@listing.child_listing} />
        </div>
      <% end %>
    </div>
    """
  end

  def field(%{field: %{__struct__: Template}} = assigns) do
    class = Keyword.get(assigns.field.opts, :class)
    columns = Keyword.get(assigns.field.opts, :columns)
    offset = Keyword.get(assigns.field.opts, :offset)

    assigns =
      assigns
      |> assign(:class, class)
      |> assign(:columns, columns)
      |> assign(:offset, offset)

    assigns =
      assign_new(assigns, :rendered_tpl, fn ->
        if tpl = Map.get(assigns.field, :template) do
          {:ok, parsed_template} = Liquex.parse(tpl, Brando.Villain.LiquexParser)
          context = Brando.Villain.get_base_context(assigns.entry)

          Liquex.Render.render([], parsed_template, context)
          |> elem(0)
          |> Enum.join()
          |> Phoenix.HTML.raw()
        end
      end)

    ~H"""
    <div class={render_classes([@class, "col-#{@columns}": @columns])}>
      <%= @rendered_tpl %>
    </div>
    """
  end

  def field(assigns) do
    attr = assigns.schema.__attribute__(assigns.field.name)
    entry_field = Map.get(assigns.entry, assigns.field.name)
    class = Keyword.get(assigns.field.opts, :class)
    columns = Keyword.get(assigns.field.opts, :columns)
    offset = Keyword.get(assigns.field.opts, :offset)
    size = Keyword.get(assigns.field.opts, :size)

    assigns =
      assigns
      |> assign(:attr, attr)
      |> assign(:entry_field, entry_field)
      |> assign(:class, class)
      |> assign(:columns, columns)
      |> assign(:offset, offset)
      |> assign(:size, size)

    ~H"""
    <%= case @field.type do %>
      <% :image -> %>
        <div class={render_classes([@class, "col-#{@columns}": @columns, "offset-#{@offset}": @offset])}>
          <Content.image image={@entry_field} size={@size || :thumb} />
        </div>

      <% :children_button -> %>
        <div
          class={render_classes([@class, "col-#{@columns}": @columns, "offset-#{@offset}": @offset])}>
          <.live_component module={ChildrenButton}
            id={"#{@entry.id}-children-button"}
            fields={@field.name}
            entry={@entry}
            {@field.opts} />
        </div>

      <% :language -> %>
        <div
          class={render_classes([@class, {:"col-#{@columns}", @columns}, {:"offset-#{@offset}", @offset}])}>
          <Badge.language language={@entry_field} />
        </div>

      <% :url -> %>
        <div
          class={render_classes([@class, "col-1", {:"offset-#{@offset}", @offset}])}>
          <a href={@schema.__absolute_url__(@entry)} target="_blank">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M18.364 15.536L16.95 14.12l1.414-1.414a5 5 0 1 0-7.071-7.071L9.879 7.05 8.464 5.636 9.88 4.222a7 7 0 0 1 9.9 9.9l-1.415 1.414zm-2.828 2.828l-1.415 1.414a7 7 0 0 1-9.9-9.9l1.415-1.414L7.05 9.88l-1.414 1.414a5 5 0 1 0 7.071 7.071l1.414-1.414 1.415 1.414zm-.708-10.607l1.415 1.415-7.071 7.07-1.415-1.414 7.071-7.07z"/></svg>
          </a>
        </div>
    <% end %>
    """
  end

  defp process_actions(actions, language, entry_id) do
    Enum.map(actions, fn
      %{event: event} = action when is_binary(event) ->
        %{action | event: JS.push(event, value: %{language: language, id: entry_id})}

      action ->
        action
    end)
  end

  attr :schema, :atom
  attr :content_language, :string
  attr :entry, :map
  attr :listing, :map

  def entry_menu(assigns) do
    language = Map.get(assigns.entry, :language)
    processed_actions = process_actions(assigns.listing.actions, language, assigns.entry.id)
    default_actions? = assigns.listing.default_actions

    ctx = assigns.schema.__modules__.context
    singular = assigns.schema.__naming__.singular
    translated_singular = assigns.schema.__translations__[:naming][:singular]

    has_duplicate_fn? = {:"duplicate_#{singular}", 2} in ctx.__info__(:functions)

    duplicate_langs? =
      assigns.schema.has_trait(Brando.Trait.Translatable) && has_duplicate_fn? &&
        Enum.count(Brando.config(:languages)) > 1

    assigns =
      assigns
      |> assign(:language, language)
      |> assign(:default_actions?, default_actions?)
      |> assign(:processed_actions, processed_actions)
      |> assign(:id, "entry-dropdown-#{assigns.listing.name}-#{assigns.entry.id}")
      |> assign(:has_duplicate_fn?, has_duplicate_fn?)
      |> assign(:duplicate_langs?, duplicate_langs?)
      |> assign(:translated_singular, translated_singular)
      |> assign(
        :duplicate_langs,
        get_duplication_langs(assigns.content_language, duplicate_langs?)
      )

    ~H"""
    <CircleDropdown.render id={@id}>
      <%= if @default_actions? do %>
        <li>
          <button
            id={"action_#{@listing.name}_edit_entry_#{@entry.id}"}
            phx-value-id={@entry.id}
            phx-value-language={@language}
            phx-click="edit_entry">
            <%= gettext "Edit" %> <%= @translated_singular %>
          </button>
        </li>
        <li>
          <button
            id={"action_#{@listing.name}_delete_entry_#{@entry.id}"}
            phx-hook="Brando.ConfirmClick"
            phx-confirm-click-message={gettext("Are you sure you want to delete this entry?")}
            phx-confirm-click={JS.push("delete_entry")}
            phx-value-language={@language}
            phx-value-id={@entry.id}>
            <%= gettext "Delete" %> <%= @translated_singular %>
          </button>
        </li>
        <li :if={@has_duplicate_fn?}>
          <button
            id={"action_#{@listing.name}_duplicate_entry_#{@entry.id}"}
            phx-value-id={@entry.id}
            phx-value-language={@language}
            phx-click="duplicate_entry">
            <%= gettext "Duplicate" %> <%= @translated_singular %>
          </button>
        </li>
        <li :if={@duplicate_langs?} :for={lang <- @duplicate_langs}>
          <button
            id={"action_#{@listing.name}_duplicate_entry_to_lang_#{@entry.id}_lang_#{lang}"}
            phx-value-id={@entry.id}
            phx-value-language={lang}
            phx-click="duplicate_entry_to_language">
            <%= gettext "Duplicate to" %> [<%= String.upcase(lang) %>]
          </button>
        </li>
      <% end %>
      <li :for={%{event: event, label: label} = action <- @processed_actions}>
        <%= if action[:confirm] do %>
          <button
            id={"action_#{@listing.name}_#{Brando.Utils.slugify(label)}_#{@entry.id}"}
            phx-hook="Brando.ConfirmClick"
            phx-confirm-click-message={action[:confirm]}
            phx-confirm-click={event}
            phx-value-language={@language}
            phx-value-id={@entry.id}>
            <%= g(@schema, label) %>
          </button>
        <% else %>
          <button
            id={"action_#{@listing.name}_#{Brando.Utils.slugify(label)}_#{@entry.id}"}
            phx-value-id={@entry.id}
            phx-value-language={@language}
            phx-click={event}>
            <%= g(@schema, label) %>
          </button>
        <% end %>
      </li>
      <li :if={Map.has_key?(@entry, :deleted_at) && not is_nil(@entry.deleted_at)}>
        <button
          id={"action_#{@listing.name}_undelete_#{@entry.id}"}
          phx-value-id={@entry.id}
          phx-value-language={@language}
          phx-click="undelete_entry">
          <%= gettext "Undelete" %> <%= @translated_singular %>
        </button>
      </li>
    </CircleDropdown.render>
    """
  end

  def handle(assigns) do
    ~H"""
    <div class="col-1 seq">
      <div class="center sequence-handle">
        <svg width="15" height="15" viewBox="0 0 15 15" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="1.5" cy="1.5" r="1.5"></circle><circle cx="7.5" cy="1.5" r="1.5"></circle><circle cx="13.5" cy="1.5" r="1.5"></circle><circle cx="1.5" cy="7.5" r="1.5"></circle><circle cx="7.5" cy="7.5" r="1.5"></circle><circle cx="13.5" cy="7.5" r="1.5"></circle><circle cx="1.5" cy="13.5" r="1.5"></circle><circle cx="7.5" cy="13.5" r="1.5"></circle><circle cx="13.5" cy="13.5" r="1.5"></circle></svg>
      </div>
    </div>
    """
  end

  def status(assigns) do
    publish_at = Map.get(assigns.entry, :publish_at, nil)
    assigns = assign(assigns, :publish_at, publish_at)

    ~H"""
    <%= if @soft_delete? and @entry.deleted_at do %>
      <div class="status">
        <div center="true">
          <svg data-testid="status-deleted" xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 15 15"><circle r="7.5" cy="7.5" cx="7.5" class="deleted"></circle></svg>
        </div>
      </div>
    <% else %>
      <div class="status">
        <div phx-click={toggle_dropdown("#status-dropdown-#{make_id(@entry)}")}>
          <.status_circle status={@entry.status} publish_at={@publish_at} />
          <.status_dropdown id={"status-dropdown-#{make_id(@entry)}"} entry_id={@entry.id} schema={@entry.__struct__} />
        </div>
      </div>
    <% end %>
    """
  end

  def status_dropdown(assigns) do
    assigns = assign(assigns, :statuses, statuses())

    ~H"""
    <div class="status-dropdown hidden" id={@id}>
      <button
        :for={status <- @statuses}
        type="button"
        phx-click={JS.push("set_status", value: %{id: @entry_id, status: status, schema: @schema}) |> toggle_dropdown("##{@id}")}>
        <.status_circle status={status} /> <%= render_status_label(status) %>
      </button>
    </div>
    """
  end

  def status_circle(%{status: :pending, publish_at: publish_at} = assigns)
      when not is_nil(publish_at) do
    ~H"""
    <svg
      data-testid="status-pending"
      width="15"
      height="15"
      viewBox="0 0 15 15"
      fill="none"
      xmlns="http://www.w3.org/2000/svg">
      <circle class="pending" cx="7.5" cy="7.5" r="7.5" />
      <line x1="7.5" y1="3" x2="7.5" y2="7" stroke="white" />
      <line x1="3.5" y1="7.5" x2="8" y2="7.5" stroke="white" />
    </svg>
    """
  end

  def status_circle(%{status: _status} = assigns) do
    ~H"""
    <svg
      data-testid={"status-#{@status}"}
      xmlns="http://www.w3.org/2000/svg"
      width="15"
      height="15"
      viewBox="0 0 15 15">
      <circle r="7.5" cy="7.5" cx="7.5" class={@status} />
    </svg>
    """
  end

  def alternates(%{entry: %{alternate_entries: %Ecto.Association.NotLoaded{}}} = assigns),
    do: ~H""

  def alternates(%{entry: %{alternate_entries: alternate_entries}} = assigns) do
    assigns =
      assigns
      |> assign(:alternate_entries?, Enum.count(alternate_entries) > 0)
      |> assign(:identifiers, Identifier.identifiers_for!(alternate_entries))

    ~H"""
    <div class="col-1">
      <button type="button" class={render_classes(["btn-icon-subtle"])} disabled={!@alternate_entries?} phx-click={show_modal("#entry-#{@entry.id}-alternates")}>
        <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 20 20" fill="currentColor" class="w-5 h-5">
          <path d="M7.75 2.75a.75.75 0 00-1.5 0v1.258a32.987 32.987 0 00-3.599.278.75.75 0 10.198 1.487A31.545 31.545 0 018.7 5.545 19.381 19.381 0 017 9.56a19.418 19.418 0 01-1.002-2.05.75.75 0 00-1.384.577 20.935 20.935 0 001.492 2.91 19.613 19.613 0 01-3.828 4.154.75.75 0 10.945 1.164A21.116 21.116 0 007 12.331c.095.132.192.262.29.391a.75.75 0 001.194-.91c-.204-.266-.4-.538-.59-.815a20.888 20.888 0 002.333-5.332c.31.031.618.068.924.108a.75.75 0 00.198-1.487 32.832 32.832 0 00-3.599-.278V2.75z" />
          <path fill-rule="evenodd" d="M13 8a.75.75 0 01.671.415l4.25 8.5a.75.75 0 11-1.342.67L15.787 16h-5.573l-.793 1.585a.75.75 0 11-1.342-.67l4.25-8.5A.75.75 0 0113 8zm2.037 6.5L13 10.427 10.964 14.5h4.073z" clip-rule="evenodd" />
        </svg>
      </button>
      <Content.modal title={gettext "Alternates"} narrow id={"entry-#{@entry.id}-alternates"}>
        <Entries.identifier
          :for={identifier <- @identifiers}
          identifier={identifier}
          select={JS.push("update_entry", value: %{url: identifier.admin_url}, target: @target)}
          remove={JS.push("remove_entry", value: %{schema: @entry.__struct__, parent_id: @entry.id, id: identifier.id}, target: @target)}
          param={identifier.id}
        />
      </Content.modal>
    </div>
    """
  end

  def alternates(assigns) do
    ~H""
  end

  def creator(%{entry: %{creator: nil}} = assigns) do
    ~H"""
    <div class="col-4">
      —
    </div>
    """
  end

  def creator(%{entry: %{creator: %{avatar: _avatar}}} = assigns) do
    ~H"""
    <div class="col-4">
      <article class="item-meta">
        <section class="avatar-wrapper">
          <div class="avatar">
            <Content.image image={@entry.creator.avatar} size={:thumb} />
          </div>
        </section>
        <section class="content">
          <div class="info">
            <div class="name">
              <%= @entry.creator.name %>
            </div>

            <div
              class="time"
              id={"entry_creator_time_icon_#{make_id(@entry)}"}
              data-popover={"The time the entry was #{@soft_delete? and @entry.deleted_at && "deleted" || "created"}"}>
              <%= if @soft_delete? and @entry.deleted_at do %>
                <%= format_datetime(@entry.deleted_at, "%d/%m/%y") %> <span>•</span> <%= format_datetime(@entry.deleted_at, "%H:%M") %>
              <% else %>
                <%= format_datetime(@entry.updated_at, "%d/%m/%y") %> <span>•</span> <%= format_datetime(@entry.updated_at, "%H:%M") %>
              <% end %>
            </div>
          </div>
        </section>
      </article>
    </div>
    """
  end

  def creator(assigns) do
    ~H"""
    """
  end

  def child_row(%{schema: schema, entry: entry, child_listing: child_listing} = assigns) do
    entry_schema = entry.__struct__

    if !child_listing do
      raise "No child listing set for `#{inspect(entry_schema)}`"
    end

    assigns =
      assigns
      |> assign_new(:alternates?, fn ->
        entry_schema.has_trait(Trait.Translatable) and schema.has_alternates?()
      end)
      |> assign_new(:creator?, fn -> entry_schema.has_trait(Trait.Creator) end)
      |> assign_new(:status?, fn -> entry_schema.has_trait(Trait.Status) end)
      |> assign_new(:soft_delete?, fn -> entry_schema.has_trait(Trait.SoftDelete) end)
      |> assign_new(:listing, fn ->
        listing_for_schema = Keyword.fetch!(child_listing, entry_schema)
        listing = Enum.find(schema.__listings__, &(&1.name == listing_for_schema))

        if !listing do
          raise "No listing `#{inspect(listing_for_schema)}` found for `#{inspect(entry_schema)}`"
        end

        listing
      end)

    assigns =
      assign_new(assigns, :sortable?, fn ->
        assigns.listing.sortable && entry_schema.has_trait(Trait.Sequenced)
      end)

    ~H"""
    <div
      class="child-row draggable"
      data-id={@entry.id}>
      <.status
        :if={@status?}
        entry={@entry}
        soft_delete?={@soft_delete?} />
      <.handle :if={@sortable?} />
      <.field
        :for={field <- @listing.fields}
        field={field}
        entry={@entry}
        schema={@schema} />
      <.alternates
        :if={@alternates?}
        entry={@entry}
        target={@target}
        schema={@schema} />
      <.creator
        :if={@creator?}
        entry={@entry}
        soft_delete?={@soft_delete?}/>
      <.entry_menu
        schema={@schema}
        entry={@entry}
        content_language={@content_language}
        listing={@listing} />
    </div>
    """
  end

  def handle_event("update_entry", %{"url" => url}, socket) do
    {:noreply, push_navigate(socket, to: url)}
  end

  def handle_event(
        "remove_entry",
        %{"schema" => schema, "parent_id" => parent_id, "id" => id},
        socket
      ) do
    alternate_schema = Module.concat(schema, Alternate)
    _ = alternate_schema.delete(id, parent_id)

    send_update(BrandoAdmin.Components.Content.List,
      id: "content_listing_#{socket.assigns.schema}_default",
      action: :update_entries
    )

    {:noreply, socket}
  end

  defp statuses() do
    [:published, :disabled, :draft, :pending]
  end

  defp render_status_label(:disabled), do: gettext("Disabled")
  defp render_status_label(:draft), do: gettext("Draft")
  defp render_status_label(:pending), do: gettext("Pending")
  defp render_status_label(:published), do: gettext("Published")
  defp render_status_label(:deleted), do: gettext("Deleted")

  defp get_duplication_langs(_, false), do: []

  defp get_duplication_langs(content_language, true) do
    Brando.config(:languages)
    |> Enum.map(& &1[:value])
    |> Enum.reject(&(&1 == content_language))
  end
end
