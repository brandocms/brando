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
        icon="languages"
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
                      value: %{id: identifier.entry_id}
                    )
                  }
                >
                  <.icon name="x" />
                </button>
              </:delete>
            </Entries.identifier>
          </div>
          <p :if={@identifiers == []} class="alternates-empty">{gettext("No linked entries yet.")}</p>
          <button
            class="btn"
            type="button"
            phx-click={JS.push("get_entries_identifiers", target: @myself)}
          >
            <.icon name="link" />{gettext("Select entries to link")}
          </button>
        </section>

        <section :if={Enum.count(@new_identifiers) > 1} class="alternates-section">
          <p>
            {gettext(
              "When you have selected more than 1 connection, you can ensure that the child alternates are linked together as well."
            )}
          </p>
          <button type="button" class="btn btn--primary" phx-click={JS.push("store_alternates", target: @myself)}>
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
                  value: %{id: identifier.entry_id}
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

  # Links are made to the entries this drawer offered, of the entry's own
  # schema, and take `:update` on both entries.
  def handle_event("select_entry", %{"id" => id}, socket) do
    entry = socket.assigns.entry
    offered = socket.assigns[:entries_identifiers] || []

    with %{} = identifier <- Enum.find(offered, &(to_string(&1.entry_id) == to_string(id))),
         :ok <- alternate(entry).add(identifier.entry_id, entry.id, actor(socket)) do
      {:noreply, add_identifier(socket, identifier)}
    else
      error -> {:noreply, refused(socket, error)}
    end
  end

  def handle_event("remove_entry", %{"id" => id}, socket) do
    entry = socket.assigns.entry

    case alternate(entry).delete(id, entry.id, actor(socket)) do
      {:error, _} = error -> {:noreply, refused(socket, error)}
      _ -> {:noreply, delete_identifier(socket, id)}
    end
  end

  def handle_event("store_alternates", _, socket) do
    # new identifiers here must be linked to eachother.
    identifiers = socket.assigns.new_identifiers
    alternate = alternate(socket.assigns.entry)
    actor = actor(socket)
    link_entries(identifiers, &alternate.add(&1, &2, actor))

    {:noreply, assign(socket, :new_identifiers, [])}
  end

  defp alternate(entry), do: Module.concat(entry.__struct__, Alternate)

  defp actor(socket), do: socket.assigns[:current_user] || BrandoAdmin.Authorization.current_actor()

  defp refused(socket, {:error, :forbidden}) do
    send(self(), {:toast, gettext("You do not have permission for this action.")})
    socket
  end

  defp refused(socket, _), do: socket

  def add_identifier(socket, identifier) do
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
