defmodule BrandoAdmin.Components.Content.List do
  @moduledoc false
  use BrandoAdmin, :live_component
  use BrandoAdmin.Translator
  use Gettext, backend: Brando.Gettext

  alias Brando.Trait.Creator
  alias Brando.Trait.Sequenced
  alias Brando.Trait.SoftDelete
  alias Brando.Trait.Status
  alias Brando.Trait.Translatable
  alias BrandoAdmin.Components.CircleDropdown
  alias BrandoAdmin.Components.Content.List.Row

  NimbleCSV.define(Brando.CSVParser, separator: "\t", escape: "\"")

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
     |> assign_filter(assigns)
     |> assign_sort()
     |> assign_entries(assigns)}
  end

  def push_query_params(%{assigns: %{uri: uri}} = socket, extra_params, drop_fields \\ []) do
    current_params = URI.decode_query(uri.query || "")

    new_params =
      current_params
      |> Map.drop(drop_fields)
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

  def handle_event("export", %{"name" => export_name}, socket) do
    send(self(), {:toast, gettext("Exporting entries...")})
    exports = socket.assigns.listing.exports
    schema = socket.assigns.schema
    context = schema.__modules__().context
    plural = schema.__naming__().plural
    selected_export = Enum.find(exports, &(to_string(&1.name) == export_name))

    {:ok, entries} = apply(context, :"list_#{plural}", [selected_export.query])
    headers = Enum.map(selected_export.fields, &to_string/1)

    rows =
      List.wrap([headers]) ++
        Enum.map(entries, fn entry ->
          for key <- selected_export.fields, do: Map.get(entry, key)
        end)

    csv_content = Brando.CSVParser.dump_to_iodata(rows)

    date =
      :timezone
      |> Brando.config()
      |> DateTime.now!()
      |> Calendar.strftime("%Y%m%d_%H%M%S")

    exports_path =
      Path.join([
        "exports",
        to_string(selected_export.type)
      ])

    target_path =
      Path.join([
        Brando.config(:media_path),
        exports_path
      ])

    File.mkdir_p!(target_path)

    target_filename = "#{plural}_export_#{date}.csv"
    File.write(Path.join(target_path, target_filename), csv_content)

    download_path = Brando.Utils.media_url(Path.join(exports_path, target_filename))

    message = """
    #{gettext("Download exports: ")}
    <a href="#{download_path}" target="_blank" download>
      #{gettext("Download")}
    </a>
    """

    {:noreply,
     push_event(socket, "b:alert", %{
       title: gettext("Download ready"),
       type: "info",
       message: message
     })}
  end

  def handle_event("next_filter_key", _, socket) do
    filters = socket.assigns.listing.filters

    current_key_idx =
      Enum.find_index(
        filters,
        &(&1.filter == socket.assigns.active_filter.filter)
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

  def handle_event("update_sort", %{"sort_key" => sort_key}, socket) do
    sorts = socket.assigns.listing.sorts
    sort = Enum.find(sorts, &(&1.key == String.to_existing_atom(sort_key)))
    sort_string = Brando.Query.order_string_to_list(sort.order)

    {:noreply,
     socket
     |> assign_sort(sort)
     |> push_query_params(%{"order" => sort_string}, ["order[asc]", "order[desc]", "order"])}
  end

  def handle_event("update_status", %{"status" => status}, %{assigns: %{list_opts: list_opts}} = socket) do
    status_atom = String.to_existing_atom(status)
    new_list_opts = update_status(list_opts, status_atom)

    if Map.get(new_list_opts, :status) do
      {:noreply, push_query_params(socket, %{"status" => status})}
    else
      {:noreply, push_query_params(socket, %{"status" => ""})}
    end
  end

  def handle_event("change_page", %{"page" => page}, socket) do
    page_number = String.to_integer(page)
    {:noreply, push_query_params(socket, %{"page" => page_number + 1})}
  end

  def handle_event("change_limit", %{"limit" => limit}, socket) do
    {:noreply, push_query_params(socket, %{"limit" => limit})}
  end

  def handle_event("select_row", %{"id" => id}, socket) do
    {:noreply, select_row(socket, String.to_integer(id))}
  end

  def handle_event("clear_selection", _, socket) do
    {:noreply, assign(socket, :selected_rows, [])}
  end

  def handle_event("sequenced", %{"sortable_id" => sortable_id} = params, %{assigns: %{schema: schema}} = socket) do
    case String.split(sortable_id, "|") do
      ["child_listing", _parent_entry_id, child_field] ->
        relation =
          Brando.Blueprint.Relations.__relation__(schema, String.to_existing_atom(child_field))

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

    socket =
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
      |> assign_new(:alternates?, fn ->
        schema.has_trait(Translatable) and schema.has_alternates?()
      end)
      |> assign_new(:creator?, fn -> schema.has_trait(Creator) end)
      |> assign_new(:listing, fn ->
        listing_name = Map.get(assigns, :listing, :default)
        listing = Enum.find(listings, &(&1.name == listing_name))

        if !listing do
          raise "No listing `#{inspect(listing_name)}` found for `#{inspect(schema)}`"
        end

        listing
      end)

    assign_new(socket, :sortable?, fn ->
      socket.assigns.listing.sortable && schema.has_trait(Sequenced)
    end)
  end

  defp assign_filter(%{assigns: %{listing: %{filters: filters}}} = socket, _assigns) do
    assign_new(socket, :active_filter, fn -> List.first(filters) end)
  end

  defp assign_sort(%{assigns: %{listing: %{sorts: sorts}, params: params}} = socket) do
    assign_new(socket, :active_sort, fn ->
      default_sort = List.first(sorts)
      param_order = get_in(params, ["order"])

      cond do
        # no param order, use default
        is_nil(param_order) ->
          default_sort

        # param order is a string
        is_binary(param_order) ->
          # find matching sort

          Enum.find(sorts, default_sort, fn sort ->
            Brando.Query.order_string_to_list(sort.order) ==
              Brando.Query.order_string_to_list(param_order)
          end)

        # param order is a keyword list
        is_list(param_order) ->
          # find matching sort
          Enum.find(sorts, default_sort, fn sort ->
            Brando.Query.order_string_to_list(sort.order) == param_order
          end)

        is_map(param_order) ->
          # find matching sort
          Enum.find(sorts, default_sort, fn sort ->
            Brando.Query.order_string_to_list(sort.order) ==
              Enum.map(Map.to_list(param_order), fn {k, v} ->
                {String.to_existing_atom(k), String.to_existing_atom(v)}
              end)
          end)
      end
    end)
  end

  defp assign_sort(socket, sort) do
    assign(socket, :active_sort, sort)
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

    sanitized_list_opts = sanitize_list_opts(list_opts)

    {:ok, entries} = apply(context, :"list_#{plural}", [sanitized_list_opts])

    socket
    |> assign(:list_opts, list_opts)
    |> assign(:entries, entries)
    |> assign(:content_language, content_language)
  end

  defp sanitize_list_opts(%{filter: filters} = list_opts) do
    sanitized_filters =
      Enum.reduce(filters, %{}, fn {k, v}, acc ->
        Map.put(acc, k, Brando.Query.sanitize_ilike_pattern(v))
      end)

    Map.put(list_opts, :filter, sanitized_filters)
  end

  defp sanitize_list_opts(list_opts) do
    list_opts
  end

  defp build_list_opts(listing, schema, content_language) do
    %{paginate: true, limit: listing.limit}
    |> maybe_merge_listing_query(listing)
    |> maybe_merge_content_language(schema, content_language)
    |> maybe_preload_creator(schema)
    |> maybe_preload_alternates(schema)
    |> preload_assets(schema)
    |> maybe_order_by(schema, listing)
  end

  defp maybe_merge_listing_query(query_params, listing) do
    # check if preload is a function
    listing_query_preloads = Brando.Utils.try_path(listing, [:query, :preload])

    preloads =
      cond do
        listing_query_preloads && is_function(listing_query_preloads) ->
          listing_query_preloads.()

        listing_query_preloads ->
          listing_query_preloads

        true ->
          []
      end

    query = put_in(listing.query, [:preload], preloads)

    Map.merge(query_params, query)
  end

  defp maybe_merge_content_language(query_params, schema, content_language) do
    if schema.has_trait(Brando.Trait.Translatable) do
      Brando.Utils.deep_merge(query_params, %{language: content_language})
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

      {"limit", "0"}, new_list_opts ->
        Map.put(new_list_opts, :limit, 0)

      {"limit", limit}, new_list_opts ->
        Map.put(new_list_opts, :limit, String.to_integer(limit))

      {"order", order}, new_list_opts when is_binary(order) ->
        Map.put(new_list_opts, :order, order)

      {"order", order}, new_list_opts ->
        order =
          Enum.map(order, fn
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

  defp maybe_order_by(list_opts, schema, listing) do
    if listing.sorts == [] do
      if schema.has_trait(Sequenced) && !Map.get(list_opts, :order) do
        Map.put(list_opts, :order, [{:asc, :sequence}, {:desc, :inserted_at}])
      else
        list_opts
      end
    else
      # set the first sort as default
      first_sort = List.first(listing.sorts)
      Map.put(list_opts, :order, first_sort.order)
    end
  end

  defp maybe_preload_creator(list_opts, schema) do
    if schema.has_trait(Creator) do
      add_preload(list_opts, creator: :avatar)
    else
      list_opts
    end
  end

  defp maybe_preload_alternates(list_opts, schema) do
    if schema.has_trait(Translatable) and schema.has_alternates?() do
      preloads =
        case schema.__absolute_url_preloads__() do
          [] ->
            :alternate_entries

          extracted_preloads ->
            [alternate_entries: extracted_preloads]
        end

      add_preload(list_opts, preloads)
    else
      list_opts
    end
  end

  defp preload_assets(list_opts, schema) do
    preloads =
      schema
      |> Brando.Blueprint.Assets.__assets__()
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

  defp update_status(%{status: current_status} = list_opts, status) when current_status == status do
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
      {gettext("Active filters")} &rarr;
      <button :for={{name, value} <- @active_filters} class="filter" phx-click={@delete} phx-value-filter={name}>
        <div class="icon-wrapper"><.icon name="hero-x-circle" /></div>
        {name}: {inspect(value)}
      </button>
    </div>
    """
  end

  # Pagination button component
  attr :page_number, :integer, required: true
  attr :current_page, :integer, required: true
  attr :change_page, :any, required: true

  def pagination_button(assigns) do
    ~H"""
    <button
      type="button"
      class={[@page_number == @current_page && "active"]}
      phx-click={@change_page}
      phx-value-page={@page_number - 1}
    >
      {@page_number}
    </button>
    """
  end

  # Page size button component
  attr :page_size, :integer, required: true
  attr :current_page_size, :integer, required: true
  attr :change_limit, :any, required: true
  attr :label, :string, default: nil

  def page_size_button(assigns) do
    label = assigns.label || to_string(assigns.page_size)

    assigns =
      assigns
      |> assign(:is_active, assigns.page_size == assigns.current_page_size)
      |> assign(:label, label)

    ~H"""
    <button
      type="button"
      class={[
        "limit-button",
        @is_active && "active"
      ]}
      phx-click={@change_limit}
      phx-value-limit={@page_size}
    >
      {@label}
    </button>
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
           change_page: change_page,
           change_limit: change_limit
         } = assigns
       ) do
    showing_start = get_showing_start(page_size, current_page)
    showing_end = get_showing_end(page_size, current_page, total_entries)
    has_entries = total_entries > 0
    page_numbers = 1..total_pages

    assigns =
      assigns
      |> assign(:change_page, change_page)
      |> assign(:change_limit, change_limit)
      |> assign(:current_page, current_page)
      |> assign(:total_entries, total_entries)
      |> assign(:page_size, page_size)
      |> assign(:has_entries, has_entries)
      |> assign(:showing_start, showing_start)
      |> assign(:showing_end, showing_end)
      |> assign(:page_numbers, page_numbers)

    ~H"""
    <div class="pagination">
      <div class="pagination-entries">
        &rarr; {@total_entries} {gettext("entries")}
        <%= if @has_entries do %>
          | {gettext("showing")} {@showing_start}-{@showing_end}
        <% end %>
        — {gettext("Per page:")}
        <.page_size_button page_size={25} current_page_size={@page_size} change_limit={@change_limit} /> /
        <.page_size_button page_size={50} current_page_size={@page_size} change_limit={@change_limit} /> /
        <.page_size_button page_size={0} current_page_size={@page_size} change_limit={@change_limit} label={gettext("All")} />
      </div>
      <div class="pagination-buttons">
        <.pagination_button
          :for={page_number <- @page_numbers}
          page_number={page_number}
          current_page={@current_page}
          change_page={@change_page}
        />
      </div>
    </div>
    """
  end

  # Helper functions for pagination
  defp get_showing_start(page_size, current_page) do
    page_size * current_page - page_size + 1
  end

  defp get_showing_end(page_size, current_page, total_entries) do
    showing_end = min(page_size * current_page, total_entries)
    # If showing_end is 0 and we have entries, show the total
    if showing_end == 0 and total_entries > 0, do: total_entries, else: showing_end
  end

  # Filter input component
  attr :filter, :map, required: true
  attr :active_filter, :map, required: true
  attr :schema, :atom, required: true
  attr :update_filter, :any, required: true
  attr :next_filter_key, :any, required: true
  attr :filters_count, :integer, required: true

  def filter_input(assigns) do
    ~H"""
    <div class={[
      "filter",
      @filter.filter == @active_filter.filter && "visible"
    ]}>
      <button class="filter-key" phx-click={@next_filter_key}>
        <span>
          {g(@schema, @filter.label)}
          <%= if @filters_count > 1 do %>
            &darr;
          <% end %>
        </span>
      </button>
      <.form
        for={%{}}
        as={:filter_form}
        phx-change={@update_filter}
        phx-window-keydown={JS.focus(to: "#listing-filter-#{@filter.filter}")}
        phx-key="f"
        onkeydown="return event.key != 'Enter';"
      >
        <input
          id={"listing-filter-#{@filter.filter}"}
          type="text"
          name="q"
          value=""
          placeholder={gettext("Filter")}
          autocomplete="off"
          phx-debounce="400"
        />
        <input type="hidden" name="filter" value={@active_filter.filter} />
      </.form>
    </div>
    """
  end

  # Export button component
  attr :exports, :list, required: true
  attr :schema, :atom, required: true
  attr :select_export, :any, required: true

  def export_dropdown(assigns) do
    ~H"""
    <div :if={@exports != []} class="exports">
      {gettext("Export")}
      <CircleDropdown.render id="listing-exports-dropdown">
        <button :for={export <- @exports} type="button" phx-value-name={export.name} phx-click={@select_export}>
          {g(@schema, export.label)} <span class="shortcut">{export.type}</span>
        </button>
      </CircleDropdown.render>
    </div>
    """
  end

  defp tools(assigns) do
    assigns =
      assigns
      |> assign(:active_filter, assigns.active_filter)
      |> assign(:active_sort, assigns.active_sort)
      |> assign(:list_opts, assigns.list_opts)
      |> assign_new(:has_status?, fn -> assigns.schema.has_trait(Brando.Trait.Status) end)
      |> assign_new(:schema, fn -> assigns.schema end)
      |> assign_new(:listing, fn -> assigns.listing end)
      |> assign_new(:update_sort, fn -> assigns.update_sort end)
      |> assign_new(:update_filter, fn -> assigns.update_filter end)
      |> assign_new(:delete_filter, fn -> assigns.delete_filter end)
      |> assign_new(:update_status, fn -> assigns.update_status end)
      |> assign_new(:next_filter_key, fn -> assigns.next_filter_key end)
      |> assign_new(:statuses, fn -> get_statuses(assigns.schema) end)
      |> assign_new(:filters, fn -> assigns.listing.filters end)
      |> assign_new(:sorts, fn -> assigns.listing.sorts end)

    ~H"""
    <div class="list-tools-wrapper">
      <div class="list-tools">
        <%= if @has_status? do %>
          <div class="statuses">
            <.status :for={status <- @statuses} status={status} list_opts={@list_opts} on_update_status={@update_status} />
          </div>
        <% end %>

        <div class="filters">
          <.filter_input
            :for={filter <- @filters}
            filter={filter}
            active_filter={@active_filter}
            schema={@schema}
            update_filter={@update_filter}
            next_filter_key={@next_filter_key}
            filters_count={Enum.count(@filters)}
          />
        </div>

        <.export_dropdown exports={@exports} schema={@schema} select_export={@select_export} />
      </div>
      <div class="list-filters-and-sorts">
        <%= if @list_opts[:filter] do %>
          <.active_filters active_filters={@list_opts[:filter]} filters={@filters} delete={@delete_filter} />
        <% end %>
        <%= if @sorts != [] do %>
          <.sorts active_sort={@active_sort} sorts={@sorts} schema={@schema} on_update={@update_sort} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :active_sort, :map, required: true
  attr :sorts, :list, required: true
  attr :schema, :atom, required: true
  attr :on_update, :any, required: true

  def sorts(assigns) do
    ~H"""
    <div class="sorts">
      {gettext("Sort by")} &rarr;
      <.simple_dropdown id="sorts-dropdown" label={g(@schema, @active_sort.label)}>
        <:options>
          <li>
            <button :for={sort <- @sorts} type="button" phx-click={@on_update} phx-value-sort_key={sort.key}>
              {raw(g(@schema, sort.label))}
            </button>
          </li>
        </:options>
      </.simple_dropdown>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, default: gettext("Select")
  slot :options, required: true

  def simple_dropdown(assigns) do
    assigns = assign(assigns, :label, raw(assigns.label))

    ~H"""
    <div class="simple-dropdown wrapper">
      <button
        class="simple-dropdown-button"
        data-testid="simple-dropdown-button"
        type="button"
        phx-click={toggle_dropdown("##{@id}")}
        phx-click-away={hide_dropdown("##{@id}")}
      >
        {@label} <span class="icon">▾</span>
      </button>
      <ul data-testid="simple-dropdown-content" class="simple-dropdown-content hidden" id={@id}>
        {render_slot(@options, @id)}
      </ul>
    </div>
    """
  end

  attr :status, :atom, required: true
  attr :on_update_status, :any, required: true
  attr :list_opts, :list, required: true

  def status(assigns) do
    rendered_status_label = render_status_label(assigns.status)
    active_class = active_status_class(assigns.list_opts, assigns.status)

    assigns =
      assigns
      |> assign(:active_class, active_class)
      |> assign(:rendered_status_label, rendered_status_label)

    ~H"""
    <button
      phx-click={@on_update_status}
      phx-value-status={@status}
      class={[
        "status",
        @active_class
      ]}
      type="button"
      phx-page-loading
    >
      <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 12 12">
        <circle class={@status} r="6" cy="6" cx="6" />
      </svg>
      <span class="label">{@rendered_status_label}</span>
    </button>
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
      data-sortable-offset={@pagination_meta.offset}
      data-sortable-selector=".list-row"
    >
      <%= if Enum.empty?(@entries) do %>
        {render_slot(@empty)}
      <% end %>
      <%= for entry <- @entries do %>
        {render_slot(@inner_block, entry)}
      <% end %>
    </div>
    """
  end

  defp get_duplication_langs(_, false), do: []

  defp get_duplication_langs(content_language, true) do
    :languages
    |> Brando.config()
    |> Enum.map(& &1[:value])
    |> Enum.reject(&(&1 == content_language))
  end

  # Selection action button component
  attr :event, :string, required: true
  attr :encoded_ids, :string, required: true
  attr :language, :string, default: nil
  slot :inner_block, required: true

  def selection_action_button(assigns) do
    ~H"""
    <button phx-click={@event} phx-value-ids={@encoded_ids} {%{phx_value_language: @language} |> filter_nil_attrs()}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  # Helper function to filter out nil attributes
  defp filter_nil_attrs(attrs) do
    attrs
    |> Enum.filter(fn {_, v} -> not is_nil(v) end)
    |> Enum.into(%{})
  end

  def selected_rows(assigns) do
    ctx = assigns.schema.__modules__().context
    singular = assigns.schema.__naming__().singular

    has_duplicate_fn? = {:"duplicate_#{singular}", 2} in ctx.__info__(:functions)
    duplicate_langs? = assigns.schema.has_trait(Brando.Trait.Translatable) && has_duplicate_fn?

    assigns =
      assigns
      |> assign(:encoded_selected_rows, Jason.encode!(assigns.selected_rows))
      |> assign(:selected_rows_count, Enum.count(assigns.selected_rows))
      |> assign(
        :duplicate_langs,
        get_duplication_langs(assigns.content_language, duplicate_langs?)
      )

    ~H"""
    <div class={[
      "selected-rows",
      @selected_rows == [] && "hidden"
    ]}>
      <div class="clear-selection">
        <button phx-click="clear_selection" phx-target={@target} type="button" class="btn-outline-primary inverted">
          {gettext("Clear selection")}
        </button>
      </div>
      <div class="selection-actions">
        {gettext("With")}
        <div class="circle"><span>{@selected_rows_count}</span></div>
        {gettext("selected, perform action")}: →
        <div id="selected_rows_dropdown" class="circle-dropdown wrapper">
          <button
            class="circle-dropdown-button"
            data-testid="circle-dropdown-button"
            phx-click={toggle_dropdown("#selected-actions-dropdown-content")}
            phx-click-away={hide_dropdown("#selected-actions-dropdown-content")}
            type="button"
          >
            <svg width="40" height="40" viewBox="0 0 40 40" fill="none" xmlns="http://www.w3.org/2000/svg">
              <circle cx="20" cy="20" r="19.5" fill="#0047FF" class="main-circle inverted"></circle>
              <line x1="12" y1="12.5" x2="28" y2="12.5" stroke="white" class="inverted"></line>
              <line x1="18" y1="26.5" x2="28" y2="26.5" stroke="white" class="inverted"></line>
              <line x1="12" y1="19.5" x2="28" y2="19.5" stroke="white" class="inverted"></line>
              <circle cx="13.5" cy="26.5" r="1.5" fill="white" class="inverted"></circle>
            </svg>
          </button>
          <ul
            data-testid="circle-dropdown-content"
            class="dropdown-content hidden over"
            id="selected-actions-dropdown-content"
          >
            <%= for lang <- @duplicate_langs do %>
              <.selection_action_button
                event="duplicate_selected_to_language"
                language={lang}
                encoded_ids={@encoded_selected_rows}
              >
                {gettext("Duplicate selected to")} [{String.upcase(lang)}]
              </.selection_action_button>
            <% end %>
            <.selection_action_button event="delete_selected" encoded_ids={@encoded_selected_rows}>
              {gettext("Delete selected")}
            </.selection_action_button>
            <%= for %{event: event, label: label} <- @selection_actions do %>
              <.selection_action_button event={event} encoded_ids={@encoded_selected_rows}>
                {g(@schema, label)}
              </.selection_action_button>
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
