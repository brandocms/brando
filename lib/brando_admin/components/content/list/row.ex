defmodule BrandoAdmin.Components.Content.List.Row do
  @moduledoc false
  use BrandoAdmin, :live_component
  use BrandoAdmin.Translator
  use Gettext, backend: Brando.Gettext

  import Brando.Utils.Datetime

  alias Brando.Blueprint.Identifier
  alias Brando.Trait
  alias BrandoAdmin.Components.Badge
  alias BrandoAdmin.Components.ChildrenButton
  alias BrandoAdmin.Components.CircleDropdown
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input.Entries

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
    {:ok, assign(socket, show_children: false, child_fields: [], active_sort: nil)}
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
      class={[
        "list-row",
        "draggable",
        @selected? && "selected"
      ]}
      data-id={@entry.id}
      phx-click={@click}
      phx-value-id={@entry.id}
    >
      <div class="main-content">
        <.status :if={@status?} entry={@entry} soft_delete?={@soft_delete?} />
        <.handle :if={@sortable?} active_sort={@active_sort} />
        <%= if @listing.component do %>
          {Phoenix.LiveView.TagEngine.component(
            @listing.component,
            [entry: @entry],
            {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
          )}
        <% else %>
          <.field :for={field <- @listing.fields} field={field} entry={@entry} schema={@schema} />
        <% end %>
        <.alternates :if={@alternates?} entry={@entry} target={@myself} schema={@schema} />
        <.creator :if={@creator?} entry={@entry} soft_delete?={@soft_delete?} />
        <.entry_menu schema={@schema} content_language={@content_language} entry={@entry} listing={@listing} />
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
          data-sortable-selector=".child-row"
        >
          <.child_row
            :for={child_entry <- Map.get(@entry, child_field, [])}
            entry={child_entry}
            schema={@schema}
            target={@myself}
            content_language={@content_language}
            child_listing={@listing.child_listings}
          />
        </div>
      <% end %>
    </div>
    """
  end

  attr :class, :string, default: nil
  attr :columns, :integer, default: nil
  attr :offset, :integer, default: nil
  slot :inner_block, required: true

  def column(assigns) do
    ~H"""
    <div class={[
      @class,
      @columns && "col-#{@columns}",
      @offset && "offset-#{@offset}"
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  def field(assigns) do
    attr = Brando.Blueprint.Attributes.__attribute__(assigns.schema, assigns.field.name)
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
        <.column class={@class} columns={@columns} offset={@offset}>
          <Content.image image={@entry_field} size={@size || :thumb} />
        </.column>
      <% :children_button -> %>
        <.column class={@class} columns={@columns} offset={@offset}>
          <.live_component
            module={ChildrenButton}
            id={"#{@entry.id}-children-button"}
            fields={@field.name}
            entry={@entry}
            {@field.opts}
          />
        </.column>
      <% :language -> %>
        <.column class={@class} columns={@columns} offset={@offset}>
          <Badge.language language={@entry_field} />
        </.column>
      <% :url -> %>
        <.column class={@class} columns={1} offset={@offset}>
          <a href={@schema.__absolute_url__(@entry)} target="_blank">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18">
              <path fill="none" d="M0 0h24v24H0z" /><path d="M18.364 15.536L16.95 14.12l1.414-1.414a5 5 0 1 0-7.071-7.071L9.879 7.05 8.464 5.636 9.88 4.222a7 7 0 0 1 9.9 9.9l-1.415 1.414zm-2.828 2.828l-1.415 1.414a7 7 0 0 1-9.9-9.9l1.415-1.414L7.05 9.88l-1.414 1.414a5 5 0 1 0 7.071 7.071l1.414-1.414 1.415 1.414zm-.708-10.607l1.415 1.415-7.071 7.07-1.415-1.414 7.071-7.07z" />
            </svg>
          </a>
        </.column>
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

  # Action button component
  attr :id, :string, required: true
  attr :entry_id, :any, required: true
  attr :language, :string, required: true
  attr :event, :any, required: true
  attr :confirm, :string, default: nil
  attr :extra_attrs, :list, default: []
  slot :inner_block, required: true

  def action_button(assigns) do
    ~H"""
    <%= if @confirm do %>
      <button
        id={@id}
        phx-hook="Brando.ConfirmClick"
        phx-confirm-click-message={@confirm}
        phx-confirm-click={@event}
        phx-value-language={@language}
        phx-value-id={@entry_id}
        {@extra_attrs}
      >
        {render_slot(@inner_block)}
      </button>
    <% else %>
      <button id={@id} phx-value-id={@entry_id} phx-value-language={@language} phx-click={@event} {@extra_attrs}>
        {render_slot(@inner_block)}
      </button>
    <% end %>
    """
  end

  attr :schema, :atom
  attr :content_language, :string
  attr :entry, :map
  attr :listing, :map

  def entry_menu(assigns) do
    language = Map.get(assigns.entry, :language)
    processed_actions = process_actions(assigns.listing.actions, language, assigns.entry.id)
    default_actions? = assigns.listing.default_actions

    ctx = assigns.schema.__modules__().context
    singular = assigns.schema.__naming__().singular
    translated_singular = Brando.Blueprint.get_singular(assigns.schema)

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
        <.action_button
          id={"action_#{@listing.name}_edit_entry_#{@entry.id}"}
          entry_id={@entry.id}
          language={@language}
          event="edit_entry"
        >
          {gettext("Edit")} {@translated_singular}
        </.action_button>
        <.action_button
          id={"action_#{@listing.name}_delete_entry_#{@entry.id}"}
          entry_id={@entry.id}
          language={@language}
          event="delete_entry"
          confirm={gettext("Are you sure you want to delete this entry?")}
        >
          {gettext("Delete")} {@translated_singular}
        </.action_button>
        <.action_button
          :if={@has_duplicate_fn?}
          id={"action_#{@listing.name}_duplicate_entry_#{@entry.id}"}
          entry_id={@entry.id}
          language={@language}
          event="duplicate_entry"
        >
          {gettext("Duplicate")} {@translated_singular}
        </.action_button>
        <.action_button
          :for={lang <- @duplicate_langs}
          :if={@duplicate_langs?}
          id={"action_#{@listing.name}_duplicate_entry_to_lang_#{@entry.id}_lang_#{lang}"}
          entry_id={@entry.id}
          language={lang}
          event="duplicate_entry_to_language"
        >
          {gettext("Duplicate to")} [{String.upcase(lang)}]
        </.action_button>
      <% end %>
      <.action_button
        :for={%{event: event, label: label, confirm: confirm} <- @processed_actions}
        id={"action_#{@listing.name}_#{Brando.Utils.slugify(label)}_#{@entry.id}"}
        entry_id={@entry.id}
        language={@language}
        event={event}
        confirm={confirm}
      >
        {g(@schema, label)}
      </.action_button>
      <.action_button
        :if={Map.has_key?(@entry, :deleted_at) && not is_nil(@entry.deleted_at)}
        id={"action_#{@listing.name}_undelete_#{@entry.id}"}
        entry_id={@entry.id}
        language={@language}
        event="undelete_entry"
      >
        {gettext("Undelete")} {@translated_singular}
      </.action_button>
    </CircleDropdown.render>
    """
  end

  attr :active_sort, :any, default: nil

  def handle(assigns) do
    show_sort =
      is_nil(assigns.active_sort) ||
        (is_map(assigns.active_sort) && Map.get(assigns.active_sort, :key) == :default)

    assigns = assign(assigns, :show_sort, show_sort)

    ~H"""
    <div class="col-1 seq">
      <div class="center sequence-handle">
        <.icon :if={@show_sort} name="brando-move" />
      </div>
    </div>
    """
  end

  # Status components
  attr :entry, :map, required: true
  attr :soft_delete?, :boolean, required: true

  def status(assigns) do
    is_deleted = assigns.soft_delete? and not is_nil(assigns.entry.deleted_at)
    publish_at = Map.get(assigns.entry, :publish_at, nil)
    status_value = if is_deleted, do: :deleted, else: assigns.entry.status

    assigns =
      assigns
      |> assign(:is_deleted, is_deleted)
      |> assign(:status_value, status_value)
      |> assign(:publish_at, publish_at)
      |> assign(:entry_id, make_id(assigns.entry))

    ~H"""
    <div class="status">
      <div center={@is_deleted} phx-click={if !@is_deleted, do: toggle_dropdown("#status-dropdown-#{@entry_id}")}>
        <.status_circle status={@status_value} publish_at={@publish_at} />
        <.status_dropdown
          :if={!@is_deleted}
          id={"status-dropdown-#{@entry_id}"}
          entry_id={@entry.id}
          schema={@entry.__struct__}
        />
      </div>
    </div>
    """
  end

  # Status dropdown component
  attr :id, :string, required: true
  attr :entry_id, :any, required: true
  attr :schema, :any, required: true

  def status_dropdown(assigns) do
    assigns = assign(assigns, :statuses, statuses())

    ~H"""
    <div class="status-dropdown hidden" id={@id}>
      <.status_button :for={status <- @statuses} status={status} id={@id} entry_id={@entry_id} schema={@schema} />
    </div>
    """
  end

  # Status button component
  attr :status, :atom, required: true
  attr :id, :string, required: true
  attr :entry_id, :any, required: true
  attr :schema, :any, required: true

  def status_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={
        "set_status"
        |> JS.push(value: %{id: @entry_id, status: @status, schema: @schema})
        |> toggle_dropdown("##{@id}")
      }
    >
      <.status_circle status={@status} /> {render_status_label(@status)}
    </button>
    """
  end

  # Status circle component
  attr :status, :atom, required: true
  attr :publish_at, :any, default: nil

  def status_circle(%{status: :pending, publish_at: publish_at} = assigns) when not is_nil(publish_at) do
    ~H"""
    <svg
      data-testid="status-pending"
      width="15"
      height="15"
      viewBox="0 0 15 15"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <circle class="pending" cx="7.5" cy="7.5" r="7.5" />
      <line x1="7.5" y1="3" x2="7.5" y2="7" stroke="white" />
      <line x1="3.5" y1="7.5" x2="8" y2="7.5" stroke="white" />
    </svg>
    """
  end

  def status_circle(%{status: _status} = assigns) do
    ~H"""
    <svg data-testid={"status-#{@status}"} xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 15 15">
      <circle r="7.5" cy="7.5" cx="7.5" class={@status} />
    </svg>
    """
  end

  def alternates(%{entry: %{alternate_entries: %Ecto.Association.NotLoaded{}}} = assigns), do: ~H""

  def alternates(%{entry: %{alternate_entries: alternate_entries}} = assigns) do
    assigns =
      assigns
      |> assign(:alternate_entries?, Enum.count(alternate_entries) > 0)
      |> assign(:identifiers, Identifier.identifiers_for!(alternate_entries))

    ~H"""
    <div class="col-1">
      <button
        type="button"
        class="btn-icon-subtle"
        disabled={!@alternate_entries?}
        phx-click={show_modal("#entry-#{@entry.id}-alternates")}
      >
        <.icon name="hero-language" class="m" />
      </button>
      <Content.modal title={gettext("Alternates")} narrow id={"entry-#{@entry.id}-alternates"}>
        <Entries.dumb_identifier
          :for={identifier <- @identifiers}
          identifier={identifier}
          select={
            JS.push("update_entry",
              value: %{entry_id: identifier.entry_id, schema: identifier.schema},
              target: @target
            )
          }
        >
          <:delete>
            <button
              type="button"
              phx-click={
                JS.push("remove_entry",
                  value: %{schema: @entry.__struct__, parent_id: @entry.id, id: identifier.entry_id},
                  target: @target
                )
              }
            >
              <.icon name="hero-x-mark" />
            </button>
          </:delete>
        </Entries.dumb_identifier>
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
    assigns = assign(assigns, :entry_id, make_id(assigns.entry))

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
              {@entry.creator.name}
            </div>

            <div class="time" id={"entry_creator_time_icon_#{@entry_id}"}>
              <%= if @soft_delete? and @entry.deleted_at do %>
                {format_datetime(@entry.deleted_at, "%d/%m/%y")}
                <span>•</span> {format_datetime(@entry.deleted_at, "%H:%M")}
              <% else %>
                {format_datetime(@entry.updated_at, "%d/%m/%y")}
                <span>•</span> {format_datetime(@entry.updated_at, "%H:%M")}
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
      raise "No child listing set for entry schema `#{inspect(entry_schema)}`. " <>
              "Check your blueprint configuration for child listings."
    end

    assigns =
      assigns
      |> assign(:entry_schema, entry_schema)
      |> assign_new(:alternates?, fn ->
        entry_schema.has_trait(Trait.Translatable) and entry_schema.has_alternates?()
      end)
      |> assign_new(:creator?, fn -> entry_schema.has_trait(Trait.Creator) end)
      |> assign_new(:status?, fn -> entry_schema.has_trait(Trait.Status) end)
      |> assign_new(:soft_delete?, fn -> entry_schema.has_trait(Trait.SoftDelete) end)
      |> assign_new(:listing, fn ->
        listing_for_schema = Enum.find(child_listing, &(&1.schema == entry_schema))

        if !listing_for_schema do
          raise "No matching child listing found for entry schema `#{inspect(entry_schema)}`. " <>
                  "Available child listings: #{inspect(Enum.map(child_listing, & &1.schema))}"
        end

        listing = Enum.find(schema.__listings__(), &(&1.name == listing_for_schema.name))

        if !listing do
          available_listings = Enum.map(schema.__listings__(), & &1.name)

          raise "No listing `#{inspect(listing_for_schema.name)}` found for `#{inspect(entry_schema)}`. " <>
                  "Available listings: #{inspect(available_listings)}"
        end

        listing
      end)

    assigns =
      assign_new(assigns, :sortable?, fn ->
        assigns.listing.sortable && entry_schema.has_trait(Trait.Sequenced)
      end)

    ~H"""
    <div class="child-row draggable" data-id={@entry.id}>
      <.status :if={@status?} entry={@entry} soft_delete?={@soft_delete?} />
      <.handle :if={@sortable?} />
      <%= if @listing.component do %>
        {Phoenix.LiveView.TagEngine.component(
          @listing.component,
          [entry: @entry],
          {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
        )}
      <% else %>
        <.field :for={field <- @listing.fields} field={field} entry={@entry} schema={@schema} />
      <% end %>
      <.alternates :if={@alternates?} entry={@entry} target={@target} schema={@schema} />
      <.creator :if={@creator?} entry={@entry} soft_delete?={@soft_delete?} />
      <.entry_menu schema={@schema} entry={@entry} content_language={@content_language} listing={@listing} />
    </div>
    """
  end

  def handle_event("update_entry", %{"entry_id" => entry_id, "schema" => schema}, socket) do
    schema = Module.concat([schema])
    url = schema.__admin_route__(:update, [entry_id])
    {:noreply, push_navigate(socket, to: url)}
  end

  def handle_event("remove_entry", %{"schema" => schema, "parent_id" => parent_id, "id" => id}, socket) do
    alternate_schema = Module.concat(schema, Alternate)
    _ = alternate_schema.delete(id, parent_id)

    send_update(BrandoAdmin.Components.Content.List,
      id: "content_listing_#{socket.assigns.schema}_default",
      action: :update_entries
    )

    {:noreply, socket}
  end

  defp statuses do
    [:published, :disabled, :draft, :pending]
  end

  defp render_status_label(:disabled), do: gettext("Disabled")
  defp render_status_label(:draft), do: gettext("Draft")
  defp render_status_label(:pending), do: gettext("Pending")
  defp render_status_label(:published), do: gettext("Published")
  defp render_status_label(:deleted), do: gettext("Deleted")

  defp get_duplication_langs(_, false), do: []

  defp get_duplication_langs(content_language, true) do
    :languages
    |> Brando.config()
    |> Enum.map(& &1[:value])
    |> Enum.reject(&(&1 == content_language))
  end
end
