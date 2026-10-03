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
      <Content.drawer
        id={@id}
        title={gettext("Alternates")}
        close={@on_close}
        icon="hero-language"
        workspace
        editor
        narrow
      >
        <:info>
          <p>
            {gettext(
              "A list of entries connected to this entry. Usually this is used to link translations together for search engines."
            )}
          </p>
        </:info>
        <section class="alternates-section">
          <h3>{gettext("Currently linked entries")}</h3>
          <div :if={@identifiers != []} class="identifier-list">
            <Entries.identifier
              :for={identifier <- @identifiers}
              :key={identifier.id}
              identifier_id={identifier.id}
              available_identifiers={@identifiers}
            >
              <:delete>
                <button
                  type="button"
                  aria-label={gettext("Remove")}
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
          </div>
          <p :if={@identifiers == []} class="alternates-empty">{gettext("No linked entries yet.")}</p>
          <button
            class="workspace-button"
            type="button"
            phx-click={JS.push("get_entries_identifiers", target: @myself)}
          >
            <.icon name="hero-link" />{gettext("Select entries to link")}
          </button>
        </section>

        <section :if={Enum.count(@new_identifiers) > 1} class="alternates-section">
          <p>
            {gettext(
              "When you have selected more than 1 connection, you can ensure that the child alternates are linked together as well."
            )}
          </p>
          <button type="button" class="workspace-button primary" phx-click={JS.push("store_alternates", target: @myself)}>
            {gettext("Link children")}
          </button>
        </section>

        <section :if={@entries_identifiers != []} class="alternates-section entries-identifiers">
          <h3>{gettext("Available entries")}</h3>
          <div class="identifier-list">
            <Entries.identifier
              :for={identifier <- @entries_identifiers}
              :key={identifier.id}
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
        </section>
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
