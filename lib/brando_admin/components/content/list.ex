defmodule BrandoAdmin.Components.Content.List do
  use BrandoAdmin, :live_component
  use BrandoAdmin.Translator, "listings"

  import Brando.Gettext

  alias Brando.Trait.Creator
  alias Brando.Trait.Sequenced
  alias Brando.Trait.SoftDelete
  alias Brando.Trait.Status

  alias BrandoAdmin.Components.Content.List.Row

  def mount(socket) do
    {:ok, assign(socket, :selected_rows, [])}
  end

  def update(%{action: :update_entries} = assigns, socket) do
    {:ok, assign_entries(socket, assigns)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign_defaults(assigns)
     |> assign_listing(assigns)
     |> assign_filter(assigns)
     |> assign_entries(assigns)}
  end

  def push_query_params(%{assigns: %{uri: uri}} = socket, extra_params) do
    current_params = URI.decode_query(uri.query || "")

    new_params =
      current_params
      |> Map.merge(extra_params)
      |> Enum.filter(fn {_k, v} -> v != "" end)
      |> Plug.Conn.Query.encode()
      |> String.replace("%3A", ":")
      |> String.replace("%5B", "[")
      |> String.replace("%5D", "]")

    to =
      if String.length(new_params) > 0 do
        uri.path <> "?" <> new_params
      else
        uri.path
      end

    push_patch(socket, to: to)
  end

  def handle_event("next_filter_key", _, socket) do
    filters = socket.assigns.listing.filters

    current_key_idx =
      Enum.find_index(
        filters,
        &(&1[:filter] == socket.assigns.active_filter[:filter])
      )

    current_key_idx =
      (current_key_idx >= Enum.count(filters) - 1 && 0) ||
        current_key_idx + 1

    {:noreply, assign(socket, :active_filter, Enum.at(filters, current_key_idx))}
  end

  def handle_event("delete_filter", %{"filter" => filter_key}, socket) do
    {:noreply, push_query_params(socket, %{"filter:#{filter_key}" => ""})}
  end

  def handle_event("update_filter", %{"filter" => filter_key, "q" => ""}, socket) do
    {:noreply, push_query_params(socket, %{"filter:#{filter_key}" => ""})}
  end

  def handle_event("update_filter", %{"filter" => filter_key, "q" => query}, socket) do
    {:noreply, push_query_params(socket, %{"filter:#{filter_key}" => query})}
  end

  def handle_event(
        "update_status",
        %{"status" => status},
        %{assigns: %{list_opts: list_opts}} = socket
      ) do
    status_atom = String.to_existing_atom(status)
    new_list_opts = update_status(list_opts, status_atom)

    if Map.get(new_list_opts, :status) do
      {:noreply, push_query_params(socket, %{"status" => status})}
    else
      {:noreply, push_query_params(socket, %{"status" => ""})}
    end
  end

  def handle_event(
        "change_page",
        %{"page" => page},
        socket
      ) do
    page_number = String.to_integer(page)
    {:noreply, push_query_params(socket, %{"page" => page_number + 1})}
  end

  def handle_event("select_row", %{"id" => id}, socket) do
    {:noreply, select_row(socket, String.to_integer(id))}
  end

  def handle_event("clear_selection", _, socket) do
    {:noreply, assign(socket, :selected_rows, [])}
  end

  def handle_event(
        "sequenced",
        %{"sortable_id" => sortable_id} = params,
        %{assigns: %{schema: schema}} = socket
      ) do
    case String.split(sortable_id, "|") do
      ["child_listing", _parent_entry_id, child_field] ->
        relation = schema.__relation__(String.to_existing_atom(child_field))
        Sequenced.sequence(relation.opts.module, params)
        send(self(), {:toast, gettext("Sequence updated")})
        {:noreply, assign_entries(socket, socket.assigns)}

      ["content_listing", _] ->
        Sequenced.sequence(schema, params)
        send(self(), {:toast, gettext("Sequence updated")})
        {:noreply, assign_entries(socket, socket.assigns)}
    end
  end

  defp select_row(%{assigns: %{selected_rows: selected_rows}} = socket, id) do
    updated_selected_rows =
      if id in selected_rows do
        List.delete(selected_rows, id)
      else
        [id | selected_rows]
      end

    assign(socket, :selected_rows, updated_selected_rows)
  end

  defp assign_defaults(socket, assigns) do
    schema = assigns.schema
    context = schema.__modules__().context
    singular = schema.__naming__().singular
    plural = schema.__naming__().plural
    listings = schema.__listings__()

    socket
    |> assign(:uri, assigns.uri)
    |> assign(:params, assigns.params)
    |> assign(:current_user, assigns.current_user)
    |> assign_new(:schema, fn -> schema end)
    |> assign_new(:context, fn -> context end)
    |> assign_new(:singular, fn -> singular end)
    |> assign_new(:plural, fn -> plural end)
    |> assign_new(:listings, fn -> listings end)
    |> assign_new(:soft_delete?, fn -> schema.has_trait(SoftDelete) end)
    |> assign_new(:status?, fn -> schema.has_trait(Status) end)
    |> assign_new(:sortable?, fn -> schema.has_trait(Sequenced) end)
    |> assign_new(:creator?, fn -> schema.has_trait(Creator) end)
  end

  defp assign_listing(%{assigns: %{listings: listings, schema: schema}} = socket, assigns) do
    assign_new(socket, :listing, fn ->
      listing_name = Map.get(assigns, :listing, :default)
      listing = Enum.find(listings, &(&1.name == listing_name))

      if !listing do
        raise "No listing `#{inspect(listing_name)}` found for `#{inspect(schema)}`"
      end

      listing
    end)
  end

  defp assign_filter(%{assigns: %{listing: %{filters: filters}}} = socket, _assigns) do
    assign(socket, :active_filter, List.first(filters))
  end

  defp assign_entries(
         %{
           assigns: %{
             schema: schema,
             context: context,
             plural: plural,
             listing: listing,
             params: params,
             current_user: current_user
           }
         } = socket,
         _
       ) do
    content_language = current_user.config.content_language

    list_opts =
      listing
      |> build_list_opts(schema, content_language)
      |> params_to_list_opts(params, schema)

    {:ok, entries} = apply(context, :"list_#{plural}", [list_opts])

    socket
    |> assign(:list_opts, list_opts)
    |> assign(:entries, entries)
  end

  # TODO: Read paginate true/false from listing
  # TODO: Read limit from listing
  defp build_list_opts(listing, schema, content_language) do
    %{paginate: true, limit: 25}
    |> maybe_merge_listing_query(listing)
    |> maybe_merge_content_language(schema, content_language)
    |> maybe_preload_creator(schema)
    |> preload_assets(schema)
    |> maybe_order_by_sequence(schema)
    |> IO.inspect()
  end

  defp maybe_merge_listing_query(query_params, listing) do
    Map.merge(query_params, listing.query)
  end

  defp maybe_merge_content_language(query_params, schema, content_language) do
    if schema.has_trait(Brando.Trait.Translatable) do
      Brando.Utils.deep_merge(query_params, %{filter: %{language: content_language}})
    else
      query_params
    end
  end

  defp params_to_list_opts(list_opts, params, _) do
    Enum.reduce(params, list_opts, fn
      {"page", page_number}, new_list_opts ->
        page_number =
          page_number
          |> String.to_integer()
          |> Kernel.-(1)
          |> max(0)

        offset = Map.get(list_opts, :limit, 25) * page_number
        Map.put(new_list_opts, :offset, offset)

      {"order", order}, new_list_opts when is_binary(order) ->
        Map.put(new_list_opts, :order, order)

      {"order", order}, new_list_opts ->
        order =
          order
          |> Enum.map(fn
            {k, v} when is_binary(k) -> {String.to_existing_atom(k), String.to_existing_atom(v)}
            {k, v} -> {k, v}
          end)

        Map.put(new_list_opts, :order, order)

      {"status", value}, new_list_opts ->
        Map.put(new_list_opts, :status, String.to_existing_atom(value))

      {"filter:" <> filter_key, value}, %{filter: filters} = new_list_opts ->
        filter_atom = String.to_existing_atom(filter_key)
        filters = Map.put(filters, filter_atom, value)
        Map.put(new_list_opts, :filter, filters)

      {"filter:" <> filter_key, value}, new_list_opts ->
        filter_atom = String.to_existing_atom(filter_key)
        Map.put(new_list_opts, :filter, %{filter_atom => value})
    end)
  end

  defp maybe_order_by_sequence(list_opts, schema) do
    if schema.has_trait(Sequenced) do
      add_order_by(list_opts, [{:asc, :sequence}, {:desc, :inserted_at}])
    else
      list_opts
    end
  end

  defp add_order_by(list_opts, order_bys) when is_list(order_bys) do
    Map.update(list_opts, :order, order_bys, fn existing_ordering ->
      Enum.uniq(existing_ordering ++ order_bys)
    end)
  end

  defp maybe_preload_creator(list_opts, schema) do
    if schema.has_trait(Creator) do
      add_preload(list_opts, creator: :avatar)
    else
      list_opts
    end
  end

  defp preload_assets(list_opts, schema) do
    preloads =
      schema.__assets__()
      |> Enum.filter(&(&1.type == :image))
      |> Enum.map(& &1.name)

    add_preloads(list_opts, preloads)
  end

  defp add_preload(list_opts, preload) do
    Map.update(list_opts, :preload, [preload], fn preloads ->
      if preload in preloads, do: preloads, else: preloads ++ [preload]
    end)
  end

  defp add_preloads(list_opts, preloads) do
    Map.update(list_opts, :preload, preloads, fn existing_preloads ->
      Enum.uniq(existing_preloads ++ preloads)
    end)
  end

  defp update_status(%{status: current_status} = list_opts, status)
       when current_status == status do
    Map.delete(list_opts, :status)
  end

  defp update_status(%{status: _} = list_opts, status) do
    Map.put(list_opts, :status, status)
  end

  defp update_status(list_opts, status) do
    Map.put(list_opts, :status, status)
  end

  defp active_filters(assigns) do
    ~H"""
    <div class="active-filters">
      <%= gettext "Active filters" %> &rarr;
      <%= for {name, value} <- @active_filters do %>
        <button
          class="filter"
          phx-click={@delete}
          phx-value-filter={name}>
          &times; <%= name %>: <%= value %>
        </button>
      <% end %>
    </div>
    """
  end

  defp pagination(
         %{
           pagination_meta: %{
             page_size: page_size,
             current_page: current_page,
             total_entries: total_entries,
             total_pages: total_pages
           },
           change_page: change_page
         } = assigns
       ) do
    assigns =
      assigns
      |> assign(:change_page, change_page)
      |> assign(:current_page, current_page)
      |> assign(:total_entries, total_entries)
      |> assign(:total_pages, total_pages)
      |> assign(:showing_start, page_size * current_page - page_size + 1)
      |> assign(:showing_end, min(page_size * current_page, total_entries))

    ~H"""
    <div class="pagination">
      <div class="pagination-entries">
        &rarr; <%= @total_entries %> <%= gettext("entries") %>
        <%= if @total_entries > 0 do %>
        | <%= gettext("showing") %> <%= @showing_start %>-<%= @showing_end %>
        <% end %>
      </div>
      <%= for p <- 0..@total_pages - 1 do %>
        <button
          class={render_classes([active: p + 1 == @current_page])}
          phx-click={@change_page}
          phx-value-page={p}>
          <%= p + 1 %>
        </button>
      <% end %>
    </div>
    """
  end

  defp tools(assigns) do
    assigns =
      assigns
      |> assign(:active_filter, assigns.active_filter)
      |> assign(:list_opts, assigns.list_opts)
      |> assign_new(:has_status?, fn -> assigns.schema.has_trait(Brando.Trait.Status) end)
      |> assign_new(:schema, fn -> assigns.schema end)
      |> assign_new(:listing, fn -> assigns.listing end)
      |> assign_new(:update_filter, fn -> assigns.update_filter end)
      |> assign_new(:delete_filter, fn -> assigns.delete_filter end)
      |> assign_new(:update_status, fn -> assigns.update_status end)
      |> assign_new(:next_filter_key, fn -> assigns.next_filter_key end)
      |> assign_new(:statuses, fn -> get_statuses(assigns.schema) end)
      |> assign_new(:filters, fn -> assigns.listing.filters end)

    ~H"""
    <div class="list-tools-wrapper">
      <div class="list-tools">
        <%= if @has_status? do %>
          <div class="statuses">
            <%= for status <- @statuses do %>
              <button
                phx-click={@update_status}
                phx-value-status={status}
                class={render_classes([
                  "status",
                  active_status_class(@list_opts, status)
                ])}
                type="button"
                phx-page-loading>
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  width="12"
                  height="12"
                  viewBox="0 0 12 12">
                  <circle
                    class={status}
                    r="6"
                    cy="6"
                    cx="6" />
                </svg>
                <span class="label"><%= render_status_label(status) %></span>
              </button>
            <% end %>
          </div>
        <% end %>

        <div class="filters">
          <%= for filter <- @filters do %>
            <div class={render_classes([
              "filter",
              visible: filter[:filter] == @active_filter[:filter]
            ])}>
              <button
                class="filter-key"
                phx-click={@next_filter_key}>
                <span><%= g(@schema, filter[:label]) %></span>
              </button>
              <.form
                for={:filter_form}
                phx-change={@update_filter}
                onkeydown="return event.key != 'Enter';">
                <input
                  type="text"
                  name="q"
                  value=""
                  placeholder={gettext("Filter")}
                  autocomplete="off"
                  phx-debounce="400"
                />
                <input
                  type="hidden"
                  name="filter"
                  value={@active_filter[:filter]}
                />
              </.form>
            </div>
          <% end %>
        </div>
      </div>

      <%= if @list_opts[:filter] do %>
        <.active_filters
          active_filters={@list_opts[:filter]}
          filters={@filters}
          delete={@delete_filter} />
      <% end %>
    </div>
    """
  end

  def entries(assigns) do
    assigns = assign_new(assigns, :empty, fn -> nil end)

    ~H"""
    <div
      id={"sortable-#{@listing_name}"}
      data-target={@target}
      class="sort-container"
      phx-hook="Brando.Sortable"
      data-sortable-id={"content_listing|#{@listing_name}"}
      data-sortable-handle=".sequence-handle"
      data-sortable-selector=".list-row">
      <%= if Enum.empty?(@entries) do %>
        <%= render_slot(@empty) %>
      <% end %>
      <%= for entry <- @entries do %>
        <%= render_slot(@inner_block, entry) %>
      <% end %>
    </div>
    """
  end

  def selected_rows(assigns) do
    assigns =
      assigns
      |> assign(:encoded_selected_rows, Jason.encode!(assigns.selected_rows))
      |> assign(:selected_rows_count, Enum.count(assigns.selected_rows))

    ~H"""
    <div class={render_classes(["selected-rows", {:hidden, Enum.empty?(@selected_rows)}])}>
      <div class="clear-selection">
        <button
          phx-click="clear_selection"
          phx-target={@target}
          type="button"
          class="btn-outline-primary inverted">
          <%= gettext("Clear selection") %>
        </button>
      </div>
      <div class="selection-actions">
        <%= gettext("With") %>
        <div class="circle"><span><%= @selected_rows_count %></span></div>
        <%= gettext("selected, perform action") %>: →
        <div
          id="selected_rows_dropdown"
          class="circle-dropdown wrapper">
          <button
            class="circle-dropdown-button"
            data-testid="circle-dropdown-button"
            type="button">
            <svg width="40" height="40" viewBox="0 0 40 40" fill="none" xmlns="http://www.w3.org/2000/svg">
              <circle cx="20" cy="20" r="19.5" fill="#0047FF" class="main-circle inverted"></circle>
              <line x1="12" y1="12.5" x2="28" y2="12.5" stroke="white" class="inverted"></line>
              <line x1="18" y1="26.5" x2="28" y2="26.5" stroke="white" class="inverted"></line>
              <line x1="12" y1="19.5" x2="28" y2="19.5" stroke="white" class="inverted"></line>
              <circle cx="13.5" cy="26.5" r="1.5" fill="white" class="inverted"></circle>
            </svg>
          </button>
          <ul data-testid="circle-dropdown-content" class="dropdown-content">
            <%= for %{event: event, label: label} <- @selection_actions do %>
              <li>
                <button
                  phx-click={event}
                  phx-value-ids={@encoded_selected_rows}>
                  <%= g(@schema, label) %>
                </button>
              </li>
            <% end %>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp get_statuses(schema) do
    soft_delete? = schema.has_trait(SoftDelete)

    if soft_delete? do
      [:published, :disabled, :draft, :pending, :deleted]
    else
      [:published, :disabled, :draft, :pending]
    end
  end

  defp active_status_class(list_opts, status) do
    if active_status?(list_opts, status) do
      " active"
    else
      ""
    end
  end

  defp active_status?(%{status: current_status}, status) when current_status == status, do: true
  defp active_status?(_, _), do: false

  defp render_status_label(:disabled), do: gettext("Disabled")
  defp render_status_label(:draft), do: gettext("Draft")
  defp render_status_label(:pending), do: gettext("Pending")
  defp render_status_label(:published), do: gettext("Published")
  defp render_status_label(:deleted), do: gettext("Deleted")
end
