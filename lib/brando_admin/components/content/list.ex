defmodule BrandoAdmin.Components.Content.List do
  use Surface.LiveComponent

  import Brando.Gettext

  alias Brando.Trait.Creator
  alias Brando.Trait.Sequenced
  alias Brando.Trait.SoftDelete
  alias Brando.Trait.Status

  alias BrandoAdmin.Components.Content.List.Entries
  alias BrandoAdmin.Components.Content.List.Pagination
  alias BrandoAdmin.Components.Content.List.Row
  alias BrandoAdmin.Components.Content.List.SelectedRows
  alias BrandoAdmin.Components.Content.List.Tools

  prop listing, :any
  prop blueprint, :any
  prop current_user, :map
  prop uri, :any
  prop params, :any

  data schema, :module
  data context, :module
  data singular, :string
  data plural, :string
  data active_filter, :any
  data list_opts, :any
  data selected_rows, :list
  data entries, :list
  data status?, :boolean
  data sortable?, :boolean
  data creator?, :boolean

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

  def render(assigns) do
    ~F"""
    <div class="content-list-wrapper">
      <article class="content-list" data-moonwalk-run="brandoList">
        <Tools
          schema={@schema}
          listing={@listing}
          active_filter={@active_filter}
          list_opts={@list_opts}
          update_status="update_status"
          update_filter="update_filter"
          next_filter_key="next_filter_key"
          delete_filter="delete_filter" />

        <Entries
          target={@myself}
          listing_name={@listing.name}
          entries={entry <- @entries.entries}>
          <:empty>
            <div class="empty-list">
              <figure>
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="100" height="100"><path fill="none" d="M0 0h24v24H0z"/><path d="M12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10zm0-2a8 8 0 1 0 0-16 8 8 0 0 0 0 16z"/></svg>
              </figure>
              {gettext("No matching entries found")}
            </div>
          </:empty>
          <Row
            id={"list-row-#{@singular}-#{entry.id}"}
            entry={entry}
            sortable?={@sortable?}
            status?={@status?}
            creator?={@creator?}
            listing={@listing}
            schema={@schema}
            selected_rows={@selected_rows}
            target={@myself}
            click="select_row" />
        </Entries>

        <Pagination
          pagination_meta={@entries.pagination_meta}
          change_page="change_page" />
      </article>

      <SelectedRows
        selected_rows={@selected_rows}
        selection_actions={@listing.selection_actions}
        target={@myself} />

    </div>
    """
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

  def handle_event("sequenced", params, socket) do
    schema = socket.assigns.schema
    Sequenced.sequence(schema, params)
    send(self(), {:toast, "Sequence updated"})
    {:noreply, assign_entries(socket, socket.assigns)}
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
    blueprint = assigns.blueprint
    schema = blueprint.modules.schema
    context = blueprint.modules.context
    singular = blueprint.naming.singular
    plural = blueprint.naming.plural
    listings = blueprint.listings

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
             params: params
           }
         } = socket,
         _
       ) do
    list_opts =
      listing
      |> build_list_opts(schema)
      |> params_to_list_opts(params, schema)

    {:ok, entries} = apply(context, :"list_#{plural}", [list_opts])

    socket
    |> assign(:list_opts, list_opts)
    |> assign(:entries, entries)
  end

  # TODO: Read paginate true/false from listing
  # TODO: Read limit from listing
  defp build_list_opts(listing, schema) do
    %{paginate: true, limit: 25}
    |> maybe_merge_listing_query(listing)
    |> maybe_preload_creator(schema)
    |> maybe_order_by_sequence(schema)
  end

  defp maybe_merge_listing_query(query_params, listing) do
    Map.merge(query_params, listing.query)
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
      if order_bys in existing_ordering,
        do: existing_ordering,
        else: existing_ordering ++ order_bys
    end)
  end

  defp maybe_preload_creator(list_opts, schema) do
    if schema.has_trait(Creator) do
      add_preload(list_opts, :creator)
    else
      list_opts
    end
  end

  defp add_preload(list_opts, preload) do
    Map.update(list_opts, :preload, [preload], fn preloads ->
      if preload in preloads, do: preloads, else: preloads ++ [preload]
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
end
