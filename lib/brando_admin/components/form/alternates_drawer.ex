defmodule BrandoAdmin.Components.Form.AlternatesDrawer do
  use BrandoAdmin, :live_component
  import Brando.Gettext
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input.Entries

  alias Brando.Blueprint.Identifier

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:identifiers, fn ->
        Identifier.identifiers_for!(assigns.entry.alternate_entries)
      end)

    {:ok, socket}
  end

  attr :id, :string
  attr :entry, :map
  attr :on_close, :any
  attr :on_remove_link, :any, default: nil
  attr :entries_identifiers, :list, default: []

  def render(assigns) do
    ~H"""
    <div>
      <Content.drawer id={@id} title={gettext("Alternates")} close={@on_close}>
        <:info>
          <p>
            <%= gettext "A list of entries connected to this entry. Usually this is used to link translations together for search engines." %>
          </p>
        </:info>
        <h3 class="mb-1"><%= gettext "Currently linked entries" %></h3>
        <Entries.identifier
          :for={identifier <- @identifiers}
          identifier={identifier}
          remove={JS.push("remove_entry", target: @myself, value: %{schema: @entry.__struct__, parent_id: @entry.id, id: identifier.id})}
          param={identifier.id} />

        <button class="secondary mt-1" type="button" phx-click={JS.push("get_entries_identifiers", target: @myself)}>
          <%= gettext "Select entries to link" %>
        </button>

        <div
          :if={@entries_identifiers != []}
          class="entries-identifiers mt-3">
          <h3 class="mb-1"><%= gettext "Available entries" %></h3>
          <Entries.identifier
            :for={identifier <- @entries_identifiers}
            identifier={identifier}
            selected_identifiers={@identifiers}
            select={JS.push("select_entry", target: @myself, value: %{schema: @entry.__struct__, parent_id: @entry.id, id: identifier.id})}
            param={identifier.id} />
        </div>
      </Content.drawer>
    </div>
    """
  end

  def handle_event("get_entries_identifiers", _, socket) do
    entry = socket.assigns.entry

    {:ok, entries_identifiers} =
      Brando.Blueprint.Identifier.list_entries_for(entry.__struct__, %{
        exclude_language: entry.language
      })

    socket =
      assign(socket, :entries_identifiers, Enum.reject(entries_identifiers, &(&1.id == entry.id)))

    {:noreply, socket}
  end

  def handle_event(
        "select_entry",
        %{"schema" => schema, "parent_id" => parent_id, "id" => id},
        socket
      ) do
    alternate_schema = Module.concat(schema, Alternate)
    _ = alternate_schema.add(id, parent_id)

    {:noreply, add_identifier(socket, id)}
  end

  def handle_event(
        "remove_entry",
        %{"schema" => schema, "parent_id" => parent_id, "id" => id},
        socket
      ) do
    alternate_schema = Module.concat(schema, Alternate)
    _ = alternate_schema.delete(id, parent_id)

    {:noreply, delete_identifier(socket, id)}
  end

  def add_identifier(socket, identifier_id) do
    identifier = Enum.find(socket.assigns.entries_identifiers, &(&1.id == identifier_id))
    assign(socket, :identifiers, socket.assigns.identifiers ++ [identifier])
  end

  def delete_identifier(socket, identifier_id) do
    assign(
      socket,
      :identifiers,
      Enum.reject(socket.assigns.identifiers, &(&1.id == identifier_id))
    )
  end

  # select={JS.push("update_entry", value: %{url: identifier.admin_url}, target: @target)}
  # remove={JS.push("remove_entry", value: %{schema: @entry.__struct__, parent_id: @entry.id, id: identifier.id}, target: @target)}
end
