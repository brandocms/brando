defmodule BrandoAdmin.Components.Content.List.Row do
  use BrandoAdmin, :live_component
  import Brando.Utils.Datetime

  alias Brando.Trait
  alias BrandoAdmin.Components.Content.List.Row

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
      class={["list-row", "draggable", selected: @selected?]}
      data-id={@entry.id}
      :on-click={@click}
      phx-value-id={@entry.id}
      phx-page-loading>
      <div class="main-content">
        <%= if @sortable? do %>
          <.handle />
        <% end %>

        <%= if @status? do %>
          <.status
            entry={@entry}
            soft_delete?={@soft_delete?} />
        <% end %>

        <%= for field <- @listing.fields do %>
          <.field
            field={field}
            entry={@entry}
            schema={@schema} />
        <% end %>

        <%= if @creator? do %>
          <.creator
            entry={@entry}
            soft_delete?={@soft_delete?}/>
        <% end %>

        <.entry_menu
          entry={@entry}
          listing={@listing} />
      </div>

      <%= if @show_children do %>
        <%= for child_field <- @child_fields do %>
          <%= for child_entry <- Map.get(@entry, child_field) do %>
            <.child_row
              entry={child_entry}
              schema={@schema}
              child_listing={@listing.child_listing} />
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  def field(assigns) do
    attr = assigns.schema.__attribute__(assigns.field.name)
    entry_field = Map.get(assigns.entry, assigns.field.name)
    class = Keyword.get(assigns.field.opts, :class)
    columns = Keyword.get(assigns.field.opts, :columns)
    offset = Keyword.get(assigns.field.opts, :offset)

    assigns =
      assigns
      |> assign(:attr, attr)
      |> assign(:entry_field, entry_field)
      |> assign(:class, class)
      |> assign(:columns, columns)
      |> assign(:offset, offset)

    assigns =
      if assigns.field.__struct__ == Template do
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
      end

    ~H"""
    <%= if @rendered_tpl do %>
      <div class={[@class, "col-#{@columns}": @columns]}>
        <%= @rendered_tpl %>
      </div>
    <% else %>
      <%= case @field.type do %>
        <% :image -> %>
          <div
            class={[@class, "col-#{@columns}": @columns, "offset-#{@offset}": @offset]}>
            <%= if @entry_field do %>
              <img src={"/media/#{Map.get(@entry_field.sizes, "thumb")}"}>
            <% else %>
              <div class="img-placeholder">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><path fill="none" d="M0 0h24v24H0z"/><path d="M4.828 21l-.02.02-.021-.02H2.992A.993.993 0 0 1 2 20.007V3.993A1 1 0 0 1 2.992 3h18.016c.548 0 .992.445.992.993v16.014a1 1 0 0 1-.992.993H4.828zM20 15V5H4v14L14 9l6 6zm0 2.828l-6-6L6.828 19H20v-1.172zM8 11a2 2 0 1 1 0-4 2 2 0 0 1 0 4z"/></svg>
              </div>
            <% end %>
          </div>

        <% :children_button -> %>
          <div
            class={[{@class, true}, "col-#{@columns}": @columns, "offset-#{@offset}": @offset]}>
            <ChildrenButton.live_component
              id={"#{@entry.id}-children-button"}
              fields={@field.name}
              entry={@entry} />
          </div>

        <% :language -> %>
          <div
            class={[{@class, true}, {:"col-#{@columns}", @columns}, {:"offset-#{@offset}", @offset}]}>
            <Badge.language language={@entry_field} />
          </div>
      <% end %>
    <% end %>
    """
  end

  def entry_menu(assigns) do
    language = Map.get(assigns.entry, :language)
    assigns =
      assigns
      |> assign(:language, language)
      |> assign(:no_actions, Enum.empty?(assigns.listing.actions))

    ~H"""
    <%= unless @no_actions do %>
      <div
        id={"entry_dropdown_#{@entry.id}"}
        class="circle-dropdown wrapper"
        phx-hook="Brando.CircleDropdown">
        <button
          class="circle-dropdown-button"
          data-testid="circle-dropdown-button"
          type="button">
          <svg width="40" height="40" viewBox="0 0 40 40" fill="none" xmlns="http://www.w3.org/2000/svg">
            <circle cx="20" cy="20" r="19.5" fill="#0047FF" class="main-circle"></circle>
            <line x1="12" y1="12.5" x2="28" y2="12.5" stroke="white"></line>
            <line x1="18" y1="26.5" x2="28" y2="26.5" stroke="white"></line>
            <line x1="12" y1="19.5" x2="28" y2="19.5" stroke="white"></line>
            <circle cx="13.5" cy="26.5" r="1.5" fill="white"></circle>
          </svg>
        </button>
        <ul data-testid="circle-dropdown-content" class="dropdown-content">
          <%= for %{event: event, label: label} = action <- @listing.actions do %>
            <li>
              <%= if action[:confirm] do %>
                <button
                  id={"action_#{event}_#{@entry.id}"}
                  phx-hook="Brando.ConfirmClick"
                  phx-confirm-click-message={action[:confirm]}
                  phx-confirm-click={event}
                  phx-value-language={@language}
                  phx-value-id={@entry.id}>
                  <%= label %>
                </button>
              <% else %>
                <button
                  id={"action_#{event}_#{@entry.id}"}
                  phx-value-id={@entry.id}
                  phx-value-language={@language}
                  phx-click={event}>
                  <%= label %>
                </button>
              <% end %>
            </li>
          <% end %>
        </ul>
      </div>
    <% end %>
    """
  end

  def handle(assigns) do
    ~H"""
    <div class="col-1">
      <div class="center sequence-handle">
        <svg width="15" height="15" viewBox="0 0 15 15" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="1.5" cy="1.5" r="1.5"></circle><circle cx="7.5" cy="1.5" r="1.5"></circle><circle cx="13.5" cy="1.5" r="1.5"></circle><circle cx="1.5" cy="7.5" r="1.5"></circle><circle cx="7.5" cy="7.5" r="1.5"></circle><circle cx="13.5" cy="7.5" r="1.5"></circle><circle cx="1.5" cy="13.5" r="1.5"></circle><circle cx="7.5" cy="13.5" r="1.5"></circle><circle cx="13.5" cy="13.5" r="1.5"></circle></svg>
      </div>
    </div>
    """
  end

  def status(assigns) do
    assigns =
      assign_new(assigns, :json_statuses, fn -> json_statuses() end)

    ~H"""
    <%= cond do %>
      <% @soft_delete? and @entry.deleted_at -> %>
        <div class="status">
          <div center="true">
            <svg data-testid="status-deleted" xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 15 15"><circle r="7.5" cy="7.5" cx="7.5" class="deleted"></circle></svg>
          </div>
        </div>
      <% @entry.status == :pending and @entry.publish_at -> %>
        <div class="status">
          <div
            id={"entry_status_#{@entry.id}"}
            data-statuses={@json_statuses}
            phx-hook="Brando.StatusDropdown"
            phx-value-id={@entry.id}>
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
          </div>
        </div>
      <% true -> %>
        <div class="status">
          <div
            id={"entry_status_#{@entry.id}"}
            data-statuses={json_statuses()}
            phx-hook="Brando.StatusDropdown"
            phx-value-id={@entry.id}>
            <svg
              data-testid={"status-#{@entry.status}"}
              xmlns="http://www.w3.org/2000/svg"
              width="15"
              height="15"
              viewBox="0 0 15 15">
              <circle r="7.5" cy="7.5" cx="7.5" class={@entry.status} />
            </svg>
          </div>
        </div>
    <% end %>
    """
  end

  def creator(%{entry: %{creator: %{avatar: avatar}}} = assigns) do
    assigns =
      assign(
        assigns,
        :avatar,
        Brando.Utils.img_url(avatar, :thumb,
          prefix: "/media",
          default: "/images/admin/avatar.svg"
        )
      )

    ~H"""
    <div class="col-4">
      <article class="item-meta">
        <section class="avatar-wrapper">
          <div class="avatar">
            <img src={@avatar}>
          </div>
        </section>
        <section class="content">
          <div class="info">
            <div class="name">
              <%= @entry.creator.name %>
            </div>

            <div
              class="time"
              id={"entry_creator_time_icon_#{@entry.id}"}
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

  def child_row(%{schema: schema, entry: entry, child_listing: child_listing} = assigns) do
    assigns =
      assigns
      |> assign(:sortable?, entry.__struct__.has_trait(Trait.Sequenced))
      |> assign(:creator?, entry.__struct__.has_trait(Trait.Creator))
      |> assign(:status?, entry.__struct__.has_trait(Trait.Status))
      |> assign(:soft_delete?, entry.__struct__.has_trait(Trait.SoftDelete))
      |> assign_new(:listing, fn ->
        entry_schema = entry.__struct__

        listing_for_schema = Keyword.fetch!(child_listing, entry_schema)
        listing = Enum.find(schema.__listings__, &(&1.name == listing_for_schema))

        if !listing do
          raise "No listing `#{inspect(listing_for_schema)}` found for `#{inspect(entry_schema)}`"
        end

        listing
      end)

    ~H"""
    <div class="child-content">
      <%= if @status? do %>
        <.status
          entry={@entry}
          soft_delete?={@soft_delete?} />
      <% end %>
      <%= for field <- @listing.fields do %>
        <.field
          field={field}
          entry={@entry}
          schema={@schema} />
      <% end %>
      <%= if @creator? do %>
        <.creator
          entry={@entry}
          soft_delete?={@soft_delete?}/>
      <% end %>
      <.entry_menu
        entry={@entry}
        listing={@listing} />
    </div>
    """
  end

  defp json_statuses() do
    [:published, :disabled, :draft, :pending]
    |> Enum.map(&{&1, render_status_label(&1)})
    |> Jason.encode!()
  end

  defp render_status_label(:disabled), do: gettext("Disabled")
  defp render_status_label(:draft), do: gettext("Draft")
  defp render_status_label(:pending), do: gettext("Pending")
  defp render_status_label(:published), do: gettext("Published")
  defp render_status_label(:deleted), do: gettext("Deleted")
end
