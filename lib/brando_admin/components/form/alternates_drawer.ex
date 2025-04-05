defmodule BrandoAdmin.Components.Form.AlternatesDrawer do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input.Entries

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:new_identifiers, fn -> [] end)
      |> assign_new(:identifiers, fn ->
        {:ok, identifiers} = Brando.Content.list_identifiers_for(assigns.entry.alternate_entries)
        identifiers
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
            {gettext(
              "A list of entries connected to this entry. Usually this is used to link translations together for search engines."
            )}
          </p>
        </:info>
        <h3 class="mb-1">{gettext("Currently linked entries")}</h3>
        <Entries.identifier
          :for={identifier <- @identifiers}
          identifier_id={identifier.id}
          available_identifiers={@identifiers}
        >
          <:delete>
            <button
              type="button"
              phx-click={
                JS.push("remove_entry",
                  target: @myself,
                  value: %{schema: @entry.__struct__, parent_id: @entry.id, id: identifier.entry_id}
                )
              }
            >
              <.icon name="hero-x-mark" />
            </button>
          </:delete>
        </Entries.identifier>

        <button class="secondary mt-1" type="button" phx-click={JS.push("get_entries_identifiers", target: @myself)}>
          {gettext("Select entries to link")}
        </button>

        <div :if={Enum.count(@new_identifiers) > 1} class="mt-3">
          <p>
            {gettext(
              "When you have selected more than 1 connection, you can ensure that the child alternates are linked together as well."
            )}
          </p>
          <button type="button" class="primary mt-1" phx-click={JS.push("store_alternates", target: @myself)}>
            {gettext("Link children")}
          </button>
        </div>

        <div :if={@entries_identifiers != []} class="entries-identifiers mt-3">
          <h3 class="mb-1">{gettext("Available entries")}</h3>
          <Entries.identifier
            :for={identifier <- @entries_identifiers}
            identifier_id={identifier.id}
            selected_identifiers={@identifiers}
            available_identifiers={@entries_identifiers}
            select={
              JS.push("select_entry",
                target: @myself,
                value: %{schema: @entry.__struct__, parent_id: @entry.id, id: identifier.entry_id}
              )
            }
          />
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
      assign(
        socket,
        :entries_identifiers,
        Enum.reject(entries_identifiers, &(&1.entry_id == entry.id))
      )

    {:noreply, socket}
  end

  def handle_event("select_entry", %{"schema" => schema, "parent_id" => parent_id, "id" => id}, socket) do
    alternate_schema = Module.concat(schema, Alternate)
    _ = alternate_schema.add(id, parent_id)

    {:noreply, add_identifier(socket, id)}
  end

  def handle_event("remove_entry", %{"schema" => schema, "parent_id" => parent_id, "id" => id}, socket) do
    alternate_schema = Module.concat(schema, Alternate)
    _ = alternate_schema.delete(id, parent_id)

    {:noreply, delete_identifier(socket, id)}
  end

  def handle_event("store_alternates", _, socket) do
    # new identifiers here must be linked to eachother.
    identifiers = socket.assigns.new_identifiers
    schema = socket.assigns.entry.__struct__
    alternate_schema = Module.concat(schema, Alternate)
    link_entries(identifiers, &alternate_schema.add/2)

    {:noreply, assign(socket, :new_identifiers, [])}
  end

  def add_identifier(socket, identifier_id) do
    identifier = Enum.find(socket.assigns.entries_identifiers, &(&1.entry_id == identifier_id))

    socket
    |> assign(:identifiers, socket.assigns.identifiers ++ [identifier])
    |> update(:new_identifiers, fn new_identifiers -> new_identifiers ++ [identifier.entry_id] end)
  end

  def delete_identifier(socket, identifier_id) do
    socket
    |> assign(
      :identifiers,
      Enum.reject(socket.assigns.identifiers, &(&1.entry_id == identifier_id))
    )
    |> update(:new_identifiers, fn new_identifiers ->
      Enum.reject(new_identifiers, &(&1 == identifier_id))
    end)
  end

  defp link_entries([], _f), do: []

  defp link_entries([a | rest], f) do
    list = for b <- rest, do: f.(a, b)
    list ++ link_entries(rest, f)
  end
end
