defmodule BrandoAdmin.Components.Form.AlternatesDrawer do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.Blueprint.Identifier
  alias Brando.Translations
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input.Entries

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:new_identifiers, fn -> [] end)
      |> assign_new(:entries_identifiers, fn -> [] end)
      |> assign_versions()

    {:ok, socket}
  end

  # The entry's language versions the editor may read, from one read of its
  # set (`Brando.Translations.language_versions/3`): those linked to it, to
  # it or through another version, and those with its keys in another
  # language that are not. Identifiers are made from the entries, as the
  # listing makes them: not every schema keeps them.
  defp assign_versions(socket) do
    entry = socket.assigns.entry
    %{linked: linked, matched: matched} = Translations.language_versions(entry.__struct__, entry, actor(socket))

    socket
    |> assign(:linked, for(version <- linked, identifier = identifier(version.entry), do: {identifier, version}))
    |> assign(:unlinked_identifiers, identifiers(Enum.reject(matched, &match?(%{deleted_at: %DateTime{}}, &1))))
  end

  # A schema without an identifier template makes none. A linked version in
  # the trash is listed as deleted, so its link can still be removed.
  defp identifiers(entries), do: for(entry <- entries, identifier = identifier(entry), do: identifier)

  defp identifier(entry) do
    if identifier = Identifier.identifier_for(entry), do: trashed(identifier, entry)
  end

  defp trashed(identifier, %{deleted_at: %DateTime{}}), do: %{identifier | status: :deleted}
  defp trashed(identifier, _entry), do: identifier

  attr :id, :string
  attr :entry, :map
  attr :on_close, :any
  attr :on_remove_link, :any, default: nil

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
        <section class="alternates-section alternates-linked">
          <h3>{gettext("Currently linked entries")}</h3>
          <div :if={@linked != []} class="identifier-list">
            <Entries.dumb_identifier
              :for={{identifier, version} <- @linked}
              :key={identifier.entry_id}
              identifier={identifier}
              select={open(identifier)}
            >
              <:detail :if={version.via}>
                {gettext("Linked through %{language}", language: String.upcase(version.via))}
              </:detail>
              <:delete :if={version.linked?}>
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
            </Entries.dumb_identifier>
          </div>
          <p :if={@linked == []} class="alternates-empty">{gettext("No linked entries yet.")}</p>
          <button
            class="btn"
            type="button"
            phx-click={JS.push("get_entries_identifiers", target: @myself)}
          >
            <.icon name="link" />{gettext("Select entries to link")}
          </button>
        </section>

        <section :if={@unlinked_identifiers != []} class="alternates-section alternates-unlinked">
          <h3>{gettext("Not linked, with the same keys")}</h3>
          <p>
            {gettext(
              "These entries have this entry's keys in another language, but are not linked to it. Link one to make it this entry's version in its language."
            )}
          </p>
          <div class="identifier-list">
            <Entries.dumb_identifier
              :for={identifier <- @unlinked_identifiers}
              :key={identifier.entry_id}
              identifier={identifier}
              select={open(identifier)}
            >
              <:delete>
                <button
                  type="button"
                  aria-label={gettext("Link")}
                  phx-click={JS.push("select_entry", target: @myself, value: %{id: identifier.entry_id})}
                >
                  <.icon name="link" />
                </button>
              </:delete>
            </Entries.dumb_identifier>
          </div>
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
            <Entries.dumb_identifier
              :for={identifier <- @entries_identifiers}
              :key={identifier.entry_id}
              identifier={identifier}
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
    {:noreply, assign(socket, :entries_identifiers, candidates(socket))}
  end

  # Links are made to the entries this drawer offered, of the entry's own
  # schema, and take `:update` on both entries.
  def handle_event("select_entry", %{"id" => id}, socket) do
    entry = socket.assigns.entry
    offered = (socket.assigns[:entries_identifiers] || []) ++ socket.assigns.unlinked_identifiers

    with %{} = identifier <- Enum.find(offered, &(to_string(&1.entry_id) == to_string(id))),
         :ok <- alternate(entry).add(identifier.entry_id, entry.id, actor(socket)) do
      {:noreply, linked(socket, identifier.entry_id)}
    else
      error -> {:noreply, refused(socket, error)}
    end
  end

  def handle_event("remove_entry", %{"id" => id}, socket) do
    entry = socket.assigns.entry

    if removable?(socket, id) do
      case alternate(entry).delete(id, entry.id, actor(socket)) do
        {:error, _} = error -> {:noreply, refused(socket, error)}
        _ -> {:noreply, unlinked(socket, id)}
      end
    else
      {:noreply, socket}
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

  # Only a pair the drawer offers to remove: a version linked to the entry
  # itself, not one linked through another version
  defp removable?(socket, id),
    do:
      Enum.any?(socket.assigns.linked, fn {_identifier, version} ->
        version.linked? and to_string(version.entry.id) == to_string(id)
      end)

  defp actor(socket), do: socket.assigns[:current_user] || BrandoAdmin.Authorization.current_actor()

  defp refused(socket, {:error, :forbidden}) do
    send(self(), {:toast, gettext("You do not have permission for this action.")})
    socket
  end

  defp refused(socket, _), do: socket

  # Entries of the schema in other languages to link: from its stored
  # identifiers, which the editor's read access scopes, or made from the
  # entries for a schema that keeps none
  defp candidates(socket) do
    %schema{} = entry = socket.assigns.entry
    linked = MapSet.new(socket.assigns.linked, fn {identifier, _version} -> identifier.entry_id end)

    identifiers =
      if schema.__persist_identifier__() do
        {:ok, identifiers} = Identifier.list_entries_for(schema, %{exclude_language: entry.language})
        identifiers
      else
        schema
        |> Translations.other_language_entries(entry, actor(socket))
        |> identifiers()
      end

    Enum.reject(identifiers, &(&1.entry_id == entry.id or MapSet.member?(linked, &1.entry_id)))
  end

  defp linked(socket, entry_id) do
    socket
    |> assign_versions()
    |> update(:entries_identifiers, fn identifiers -> Enum.reject(identifiers || [], &(&1.entry_id == entry_id)) end)
    |> update(:new_identifiers, &(&1 ++ [entry_id]))
  end

  defp unlinked(socket, entry_id) do
    socket
    |> assign_versions()
    |> update(:new_identifiers, fn ids -> Enum.reject(ids, &(to_string(&1) == to_string(entry_id))) end)
  end

  defp open(identifier) do
    case identifier.schema.__admin_route__(:update, [identifier.entry_id]) do
      url when is_binary(url) -> JS.navigate(url)
      _ -> false
    end
  rescue
    _ -> false
  end

  defp link_entries([], _f), do: []

  defp link_entries([a | rest], f) do
    list = for b <- rest, do: f.(a, b)
    list ++ link_entries(rest, f)
  end
end
