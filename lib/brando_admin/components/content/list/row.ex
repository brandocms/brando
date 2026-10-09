defmodule BrandoAdmin.Components.Content.List.Row do
  @moduledoc false
  use BrandoAdmin, :live_component
  use BrandoAdmin.Translator
  use Gettext, backend: Brando.Gettext

  import Brando.Utils.Datetime

  alias Brando.Blueprint.Identifier
  alias Brando.Trait
  alias BrandoAdmin.Components.Badge
  alias BrandoAdmin.Components.ChildListingButton
  alias BrandoAdmin.Components.CircleDropdown
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input.Entries

  # prop entry, :any
  # prop selected_rows, :list
  # prop listing, :any
  # prop schema, :any
  # prop click_event, :string, required: true
  # prop sortable?, :boolean
  # prop status?, :boolean
  # prop creator?, :boolean
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
        @selected? && "selected",
        @show_children && "children-open"
      ]}
      phx-click={@click_event}
      phx-target={@target}
      phx-value-id={@entry.id}
      data-id={@entry.id}
      draggable="true"
    >
      <div class="main-content">
        <.status :if={@status?} entry={@entry} soft_delete?={@soft_delete?} />
        <.handle :if={@sortable?} active_sort={@active_sort} />
        <%= if @listing.component do %>
          {Phoenix.LiveView.TagEngine.component(
            @listing.component,
            [entry: @entry, current_user: @current_user],
            {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
          )}
        <% else %>
          <.field
            :for={field <- @listing.fields}
            :key={field.name}
            field={field}
            entry={@entry}
            schema={@schema}
            target={@myself}
          />
        <% end %>
        <.alternates :if={@alternates?} entry={@entry} target={@myself} schema={@schema} />
        <.translation_status entry={@entry} schema={@schema} />
        <.creator :if={@creator?} entry={@entry} soft_delete?={@soft_delete?} />
        <.entry_menu
          schema={@schema}
          content_language={@content_language}
          entry={@entry}
          listing={@listing}
          current_user={assigns[:current_user]}
        />
      </div>

      <%= if @show_children do %>
        <div
          :for={child_field <- @child_fields}
          :key={child_field}
          class="child-rows sort-container"
          id={"sortable-#{@entry.id}-#{child_field}"}
          data-target={@target}
          phx-hook="Brando.Sortable"
          data-sortable-id={"child_listing|#{@entry.id}|#{child_field}"}
          data-sortable-handle=".sequence-handle"
          data-sortable-selector=".child-row"
        >
          <.child_row
            :for={child_entry <- Map.get(@entry, child_field, [])}
            :key={child_entry.id}
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
          <ChildListingButton.children_button
            fields={@field.name}
            entry={@entry}
            target={@target}
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
            <.icon name="link" class="m" />
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
  attr :confirm_title, :string, default: nil
  attr :confirm_label, :string, default: nil
  attr :destructive, :boolean, default: false
  attr :describe, :string, default: nil, doc: "LiveView event that replies with the dialog's text"
  attr :extra_attrs, :list, default: []
  slot :inner_block, required: true

  def action_button(assigns) do
    ~H"""
    <%= if @confirm do %>
      <button
        id={@id}
        phx-hook="Brando.ConfirmClick"
        phx-confirm-click-message={@confirm}
        phx-confirm-click-title={@confirm_title}
        phx-confirm-click-confirm={@confirm_label}
        phx-confirm-click-destructive={@destructive}
        phx-confirm-click-describe={@describe}
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
  attr :current_user, :any, default: nil

  def entry_menu(assigns) do
    language = Map.get(assigns.entry, :language)
    processed_actions = process_actions(assigns.listing.actions, language, assigns.entry.id)
    default_actions? = assigns.listing.default_actions

    ctx = assigns.schema.__modules__().context
    singular = assigns.schema.__naming__().singular
    translated_singular = Brando.Blueprint.get_singular(assigns.schema)

    has_duplicate_fn? = {:"duplicate_#{singular}", 2} in ctx.__info__(:functions)
    has_blocks? = assigns.schema.has_trait(Brando.Trait.Blocks)

    # A synchronized schema's language versions belong to a translation group:
    # a plain copy in another language would stand outside it, so its rows
    # offer "Create translation" instead, the same as the form.
    synchronized? = Brando.Translations.synchronized?(assigns.schema)

    duplicate_langs? =
      assigns.schema.has_trait(Brando.Trait.Translatable) && has_duplicate_fn? &&
        Enum.count(Brando.config(:languages)) > 1 && not synchronized?

    {translation_source_id, translation_langs} =
      if synchronized? and has_duplicate_fn?, do: translation_targets(assigns.entry), else: {nil, []}

    ai_configured? = Brando.AI.configured?()

    assigns =
      assigns
      |> assign(:language, language)
      |> assign(:default_actions?, default_actions?)
      |> assign(:processed_actions, processed_actions)
      |> assign(:id, "entry-dropdown-#{assigns.listing.name}-#{assigns.entry.id}")
      |> assign(:has_duplicate_fn?, has_duplicate_fn?)
      |> assign(:has_blocks?, has_blocks?)
      |> assign(:duplicate_langs?, duplicate_langs?)
      |> assign(:translation_source_id, translation_source_id)
      |> assign(:translation_langs, translation_langs)
      |> assign(:ai_configured?, ai_configured?)
      |> assign(:translated_singular, translated_singular)
      |> assign(
        :duplicate_langs,
        get_duplication_langs(assigns.content_language, duplicate_langs?) -- linked_languages(assigns.entry)
      )

    ~H"""
    <CircleDropdown.render id={@id}>
      <%= if @default_actions? do %>
        <.action_button
          :if={BrandoAdmin.Authorization.allowed?(:update, @entry)}
          id={"action_#{@listing.name}_edit_entry_#{@entry.id}"}
          entry_id={@entry.id}
          language={@language}
          event="edit_entry"
        >
          {gettext("Edit")}
        </.action_button>
        <.action_button
          :if={BrandoAdmin.Authorization.allowed?(:delete, @entry)}
          id={"action_#{@listing.name}_delete_entry_#{@entry.id}"}
          entry_id={@entry.id}
          language={@language}
          event="delete_entry"
          confirm={gettext("Are you sure you want to delete this entry?")}
          confirm_title={gettext("Delete %{singular}?", singular: String.downcase(@translated_singular))}
          confirm_label={gettext("Delete")}
          describe="describe_delete"
          destructive
        >
          {gettext("Delete")}
        </.action_button>
        <.action_button
          :if={
            @has_duplicate_fn? && BrandoAdmin.Authorization.allowed?(:duplicate, @entry) &&
              BrandoAdmin.Authorization.allowed?(:create, @schema)
          }
          id={"action_#{@listing.name}_duplicate_entry_#{@entry.id}"}
          entry_id={@entry.id}
          language={@language}
          event="duplicate_entry"
        >
          {gettext("Duplicate")}
        </.action_button>
        <.action_button
          :for={lang <- @duplicate_langs}
          :if={@duplicate_langs? && BrandoAdmin.Authorization.allowed?(:duplicate, @entry)}
          :key={lang}
          id={"action_#{@listing.name}_duplicate_entry_to_lang_#{@entry.id}_lang_#{lang}"}
          entry_id={@entry.id}
          language={lang}
          event="duplicate_entry_to_language"
        >
          {gettext("Duplicate to")} [{String.upcase(lang)}]
        </.action_button>
        <.action_button
          :for={lang <- @duplicate_langs}
          :if={@duplicate_langs? and @ai_configured?}
          :key={"translate_#{lang}"}
          id={"action_#{@listing.name}_translate_entry_to_lang_#{@entry.id}_lang_#{lang}"}
          entry_id={@entry.id}
          language={lang}
          event="translate_entry_to_language"
          extra_attrs={[class: "ai-translate-action"]}
        >
          {gettext("Translate to")} [{String.upcase(lang)}] <.icon name="sparkles" />
        </.action_button>
        <.action_button
          :for={lang <- @translation_langs}
          :if={BrandoAdmin.Authorization.allowed?(:create, @schema)}
          :key={"create_translation_#{lang}"}
          id={"action_#{@listing.name}_create_translation_#{@entry.id}_lang_#{lang}"}
          entry_id={@translation_source_id}
          language={lang}
          event="create_entry_translation"
        >
          {gettext("Create translation")} [{String.upcase(lang)}]
        </.action_button>
        <.action_button
          :if={@has_blocks? && superuser?(@current_user) && BrandoAdmin.Authorization.allowed?(:publish, @entry)}
          id={"action_#{@listing.name}_rerender_entry_#{@entry.id}"}
          entry_id={@entry.id}
          language={@language}
          event="rerender_entry"
        >
          {gettext("Re-render")}
        </.action_button>
      <% end %>
      <.action_button
        :for={%{event: event, label: label, confirm: confirm} <- @processed_actions}
        :key={event}
        id={"action_#{@listing.name}_#{Brando.Utils.slugify(label)}_#{@entry.id}"}
        entry_id={@entry.id}
        language={@language}
        event={event}
        confirm={confirm}
      >
        {g(@schema, label)}
      </.action_button>
      <.action_button
        :if={
          Map.has_key?(@entry, :deleted_at) && not is_nil(@entry.deleted_at) &&
            BrandoAdmin.Authorization.allowed?(:restore, @entry)
        }
        id={"action_#{@listing.name}_undelete_#{@entry.id}"}
        entry_id={@entry.id}
        language={@language}
        event="undelete_entry"
      >
        {gettext("Undelete")}
      </.action_button>
    </CircleDropdown.render>
    """
  end

  attr :active_sort, :any, default: nil

  # Rows can only be dragged while they are shown in their stored order: under
  # any other sort a drag would reorder something the list doesn't show. The
  # column is then left out, so the row starts at its content; the sort menu
  # says which order allows dragging.
  def handle(assigns) do
    assigns = assign(assigns, :by_sequence?, ordered_by_sequence?(assigns[:active_sort]))

    ~H"""
    <div :if={@by_sequence?} class="col-1 seq">
      <div class="center sequence-handle">
        <.icon name="grip-vertical" />
      </div>
    </div>
    """
  end

  @doc false
  def ordered_by_sequence?(nil), do: true

  # Anywhere in the order: a listing may group first ("featured first, then
  # sequence") and still be shown in its stored order within each group.
  def ordered_by_sequence?(%{order: order}) do
    Enum.any?(Brando.Query.order_string_to_list(order), &match?({_direction, :sequence}, &1))
  end

  def ordered_by_sequence?(_sort), do: false

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
      |> assign(:expires_at, if(!is_deleted, do: expires_at(assigns.entry)))
      |> assign(:entry_id, make_id(assigns.entry))

    ~H"""
    <div class="status">
      <div center={@is_deleted} phx-click={if !@is_deleted, do: toggle_dropdown("#status-dropdown-#{@entry_id}")}>
        <.status_circle status={@status_value} publish_at={@publish_at} />
        <span class="listing-status-label">{render_status_label(@status_value)}</span>
        <.status_dropdown
          :if={!@is_deleted && BrandoAdmin.Authorization.allowed?(:publish, @entry)}
          id={"status-dropdown-#{@entry_id}"}
          entry_id={@entry.id}
          schema={@entry.__struct__}
        />
      </div>
      <time
        :if={@expires_at}
        class="listing-expiry"
        datetime={DateTime.to_iso8601(@expires_at)}
        title={BrandoAdmin.Dates.full(@expires_at)}
        data-testid="listing-expiry"
      >
        {gettext("Expires %{date}", date: BrandoAdmin.Dates.day(@expires_at))}
      </time>
    </div>
    """
  end

  @doc """
  When a published or scheduled entry expires (`unpublish_at`), or nil when
  it has no expiry ahead of it.
  """
  def expires_at(%{unpublish_at: %DateTime{} = unpublish_at, status: status})
      when status in [:published, :pending] do
    if DateTime.after?(unpublish_at, DateTime.utc_now()), do: unpublish_at
  end

  def expires_at(_entry), do: nil

  # Status dropdown component
  attr :id, :string, required: true
  attr :entry_id, :any, required: true
  attr :schema, :any, required: true

  def status_dropdown(assigns) do
    assigns = assign(assigns, :statuses, statuses())

    ~H"""
    <div class="status-dropdown hidden" id={@id}>
      <.status_button :for={status <- @statuses} :key={status} status={status} id={@id} entry_id={@entry_id} schema={@schema} />
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
      <span class="status-label"><.status_circle status={@status} /> {render_status_label(@status)}</span>
    </button>
    """
  end

  # Status circle component
  attr :status, :atom, required: true
  attr :publish_at, :any, default: nil

  def status_circle(%{status: :pending, publish_at: publish_at} = assigns) when not is_nil(publish_at) do
    ~H"""
    <svg
      class="status-dot"
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
    <svg
      class="status-dot"
      data-testid={"status-#{@status}"}
      xmlns="http://www.w3.org/2000/svg"
      width="15"
      height="15"
      viewBox="0 0 15 15"
    >
      <circle r="7.5" cy="7.5" cx="7.5" class={@status} />
    </svg>
    """
  end

  @doc "A status's name, e.g. for the title of its circle."
  def status_label(:published), do: gettext("Published")
  def status_label(:draft), do: gettext("Draft")
  def status_label(:pending), do: gettext("Pending")
  def status_label(:disabled), do: gettext("Deactivated")
  def status_label(status) when is_binary(status), do: status |> String.to_existing_atom() |> status_label()
  def status_label(_), do: gettext("Unpublished")

  attr :entry, :map, required: true
  attr :schema, :atom, required: true

  @doc """
  The language versions of a synchronized translation group and their open
  work (`Brando.Translations.listing_status/2`), each linking to its entry.
  """
  def translation_status(assigns) do
    assigns = assign(assigns, :versions, Map.get(assigns.entry, :translation_status))

    ~H"""
    <div :if={@versions} class="listing-translations">
      <ul aria-label={gettext("Language versions")}>
        <li :for={version <- @versions}>
          <.link
            navigate={@schema.__admin_route__(:update, [version.entry_id])}
            class={["listing-translation", "is-#{translation_state(version)}", version.entry_id == @entry.id && "is-current"]}
            title={translation_summary(version, :full)}
          >
            <span class="listing-translation-language">{String.upcase(version.language)}</span>
            <span class="listing-translation-state">{translation_summary(version, :short)}</span>
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  defp translation_state(%{role: :source}), do: "source"
  defp translation_state(%{synchronized: false}), do: "independent"
  # Only text to translate or review is work; links waiting for their own
  # translation already point at the source's target, so they only inform.
  defp translation_state(%{pending: true, counts: counts}) do
    if Map.get(counts, :translate, 0) + Map.get(counts, :review, 0) > 0, do: "work", else: "updated"
  end

  defp translation_state(_version), do: "current"

  defp translation_summary(%{role: :source}, _), do: gettext("Source")
  defp translation_summary(%{synchronized: false}, _), do: gettext("Independent")

  # The row shows the open work; the tooltip adds that the version has also
  # taken shared updates from the source.
  defp translation_summary(%{pending: true, counts: counts}, length) do
    text = Map.get(counts, :translate, 0)
    review = Map.get(counts, :review, 0)
    waiting = Map.get(counts, :awaiting_translation, 0)
    shared = Map.get(counts, :shared_update, 0)
    relinked = Map.get(counts, :relinked, 0)

    parts = translation_summary_parts(text, review, waiting, shared, length)

    cond do
      parts != [] -> Enum.join(parts, " · ")
      shared == 0 and relinked > 0 -> gettext("Links updated")
      true -> gettext("Updated from the source")
    end
  end

  defp translation_summary(_version, _), do: gettext("Up to date")

  defp translation_summary_parts(text, review, waiting, shared, length) do
    Enum.reject(
      [
        text > 0 && ngettext("%{count} to translate", "%{count} to translate", text),
        review > 0 && ngettext("%{count} to review", "%{count} to review", review),
        waiting > 0 && ngettext("%{count} link waiting", "%{count} links waiting", waiting),
        length == :full && shared > 0 && text + review == 0 && gettext("Updated from the source")
      ],
      &(&1 in [false, nil])
    )
  end

  def alternates(%{entry: %{alternate_entries: %Ecto.Association.NotLoaded{}}} = assigns), do: ~H""

  def alternates(%{entry: %{alternate_entries: alternate_entries}} = assigns) do
    assigns =
      assigns
      |> assign(:alternate_entries?, alternate_entries != [])
      # In-memory identifiers: `id` is nil, so key the rows on schema + entry_id.
      |> assign(:identifiers, Identifier.identifiers_for!(alternate_entries))

    ~H"""
    <div class="col-1 listing-alternates">
      <button
        type="button"
        aria-label={gettext("Alternates")}
        data-tooltip={gettext("Alternates")}
        class="btn-icon-subtle"
        disabled={!@alternate_entries?}
        phx-click={show_modal("#entry-#{@entry.id}-alternates")}
      >
        <.icon name="languages" class="m" />
      </button>
      <Content.modal title={gettext("Alternates")} narrow id={"entry-#{@entry.id}-alternates"}>
        <div class="identifier-list">
          <Entries.dumb_identifier
            :for={identifier <- @identifiers}
            :key={{identifier.schema, identifier.entry_id}}
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
                aria-label={gettext("Remove")}
                phx-click={
                  JS.push("remove_entry",
                    value: %{schema: @entry.__struct__, parent_id: @entry.id, id: identifier.entry_id},
                    target: @target
                  )
                }
              >
                <.icon name="x" />
              </button>
            </:delete>
          </Entries.dumb_identifier>
        </div>
      </Content.modal>
    </div>
    """
  end

  def alternates(assigns) do
    ~H""
  end

  @doc """
  Who last touched the entry, and when.

  Shows the last human editor with `edited_at` when the entry has been edited
  through a user-scoped save, otherwise the creator with `inserted_at`. It never
  pairs the creator with `updated_at`: that column moves on re-renders and
  deploys, which would read as "Evan updated this today" about an entry nobody
  opened. Soft-deleted entries show `deleted_at` instead.
  """
  def creator(%{entry: %{creator: nil, updated_by: nil}} = assigns) do
    ~H"""
    <div class="col-4">
      —
    </div>
    """
  end

  def creator(%{entry: %{creator: %{avatar: _}}} = assigns), do: editor(assigns)
  def creator(%{entry: %{updated_by: %Brando.Users.User{}}} = assigns), do: editor(assigns)

  def creator(assigns) do
    ~H"""
    """
  end

  defp editor(assigns) do
    {user, label, at} = editor_facts(assigns.entry, assigns.soft_delete?)

    assigns =
      assigns
      |> assign(:entry_id, make_id(assigns.entry))
      |> assign(:user, user)
      |> assign(:label, label)
      |> assign(:at, at)

    ~H"""
    <div class="col-4 listing-creator" aria-label={@label}>
      <article class="item-meta">
        <section class="avatar-wrapper">
          <div class="avatar" aria-hidden="true">
            <Content.image :if={@user.avatar} image={@user.avatar} size={:thumb} />
            <span :if={!@user.avatar} class="creator-initials">{String.first(@user.name || "?")}</span>
          </div>
        </section>
        <section class="content">
          <div class="info">
            <div class="name">
              {@user.name}
            </div>

            <div class="time" id={"entry_creator_time_icon_#{@entry_id}"} title={@label}>
              <%= if @at do %>
                {format_datetime(@at, "%d.%m.%y")}
                <span>•</span> {format_datetime(@at, "%H:%M")}
              <% end %>
            </div>
          </div>
        </section>
      </article>
    </div>
    """
  end

  defp editor_facts(%{deleted_at: %{} = deleted_at} = entry, true) do
    {Map.get(entry, :trashed_by) || Map.get(entry, :updated_by) || entry.creator, gettext("Deleted"), deleted_at}
  end

  defp editor_facts(%{updated_by: %Brando.Users.User{} = updated_by} = entry, _) do
    {updated_by, gettext("Edited by"), Map.get(entry, :edited_at) || entry.updated_at}
  end

  defp editor_facts(entry, _) do
    {entry.creator, gettext("Created by"), entry.inserted_at}
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
        entry_schema.has_trait(Trait.Translatable) and entry_schema.has_alternates?() and
          not Brando.Translations.synchronized?(entry_schema)
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
        <.field
          :for={field <- @listing.fields}
          :key={field.name}
          field={field}
          entry={@entry}
          schema={@schema}
          target={@target}
        />
      <% end %>
      <.alternates :if={@alternates?} entry={@entry} target={@target} schema={@schema} />
      <.translation_status entry={@entry} schema={@schema} />
      <.creator :if={@creator?} entry={@entry} soft_delete?={@soft_delete?} />
      <.entry_menu
        schema={@schema}
        entry={@entry}
        content_language={@content_language}
        listing={@listing}
        current_user={assigns[:current_user]}
      />
    </div>
    """
  end

  def handle_event("toggle_children", %{"fields" => fields}, socket) do
    child_fields = matching_child_fields(socket.assigns.entry, fields)

    {:noreply,
     socket
     |> assign(:show_children, !socket.assigns.show_children)
     |> assign(:child_fields, child_fields)}
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

  defp matching_child_fields(entry, fields) do
    entry_fields = Map.keys(entry)

    fields
    |> List.wrap()
    |> Enum.map(fn
      field when is_atom(field) -> Enum.find(entry_fields, &(&1 == field))
      field when is_binary(field) -> Enum.find(entry_fields, &(is_atom(&1) and Atom.to_string(&1) == field))
      _field -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp statuses do
    [:published, :disabled, :draft, :pending]
  end

  defp render_status_label(nil), do: gettext("Not set")
  defp render_status_label(:disabled), do: gettext("Deactivated")
  defp render_status_label(:draft), do: gettext("Draft")
  defp render_status_label(:pending), do: gettext("Pending")
  defp render_status_label(:published), do: gettext("Published")
  defp render_status_label(:deleted), do: gettext("Deleted")

  # The group's source and the languages it has no version in yet. An entry
  # outside a group becomes the source of the first translation.
  defp translation_targets(entry) do
    versions = Map.get(entry, :translation_status) || []
    source = Enum.find(versions, &(&1.role == :source))
    taken = [to_string(entry.language) | Enum.map(versions, &to_string(&1.language))]

    languages =
      for value <- Ecto.Enum.values(entry.__struct__, :language), to_string(value) not in taken, do: to_string(value)

    {(source && source.entry_id) || entry.id, languages}
  end

  # Languages the entry already has a version in, through its alternates: a
  # copy into one of those would give it a second.
  defp linked_languages(%{alternate_entries: alternates}) when is_list(alternates) do
    for %{language: language} = alternate <- alternates, is_nil(Map.get(alternate, :deleted_at)), do: to_string(language)
  end

  defp linked_languages(_entry), do: []

  defp get_duplication_langs(_, false), do: []

  defp get_duplication_langs(content_language, true) do
    :languages
    |> Brando.config()
    |> Enum.map(& &1[:value])
    |> Enum.reject(&(&1 == content_language))
  end

  defp superuser?(%{role: :superuser}), do: true
  defp superuser?(_user), do: false
end
