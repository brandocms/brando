defmodule BrandoAdmin.Components.Form.RemoteFieldChangesTest do
  use ExUnit.Case, async: true

  alias BrandoAdmin.Components.Form
  alias Ecto.Changeset
  alias Phoenix.Component

  defmodule Entry do
    use Ecto.Schema

    embedded_schema do
      field :title, :string
      field :body, :string
      field :caption, :string
    end

    def __rich_text_fields__, do: [:body, :caption]
  end

  defp socket(assigns \\ []) do
    entry = %Entry{id: "entry-1", title: "Stored title", body: "<p>Stored body</p>", caption: "<p>Caption</p>"}
    changeset = Changeset.change(entry, body: "<p>Local draft</p>")

    Component.assign(
      %Phoenix.LiveView.Socket{},
      Keyword.merge(
        [
          schema: Entry,
          entry: entry,
          singular: "entry",
          current_user: %{id: 1},
          form: Component.to_form(changeset, as: "entry"),
          tiptap_epoch: "mounted-form",
          dirty_fields: [],
          synced_values: %{},
          unshipped_fields: MapSet.new(),
          replaced_values: %{},
          held_remote: %{},
          field_clocks: %{}
        ],
        assigns
      )
    )
  end

  test "remote field messages apply their list of changes without replacing untouched rich text" do
    changes = [%{field: :title, value: "Remote title", assoc?: false, clock: {1, "remote"}}]

    assert {:ok, updated} = Form.update(%{event: "apply_remote_field_changes", changes: changes}, socket())
    assert updated.assigns.form[:title].value == "Remote title"
    assert updated.assigns.form[:body].value == "<p>Local draft</p>"

    events = Phoenix.LiveView.Utils.get_push_events(updated)
    assert ["b:component:remount", %{skip_rich_text: true}] in events
    refute Enum.any?(events, fn [event, _] -> event == "b:tiptap:update" end)
  end

  test "remote rich-text changes target only their own editor, including an empty replacement" do
    changes = [
      %{field: :title, value: "Remote title", assoc?: false, clock: {1, "remote"}},
      %{field: :body, value: "", assoc?: false, clock: {1, "remote"}}
    ]

    assert {:ok, updated} = Form.update(%{event: "apply_remote_field_changes", changes: changes}, socket())
    assert updated.assigns.form[:body].value == ""
    assert updated.assigns.form[:caption].value == "<p>Caption</p>"

    assert [["b:tiptap:update", payload]] =
             updated
             |> Phoenix.LiveView.Utils.get_push_events()
             |> Enum.filter(fn [event, _] -> event == "b:tiptap:update" end)

    assert payload.id == "entry_body-rich-text"
    assert payload.html == ""
    assert payload.epoch == "mounted-form"
    assert payload.revision == 1
  end

  test "a remote change to the field being typed in waits until the editor leaves it" do
    changes = [
      %{field: :title, value: "Remote title", assoc?: false, clock: {1, "remote"}},
      %{field: :body, value: "<p>Older remote body</p>", assoc?: false, clock: {1, "remote"}}
    ]

    socket = socket(focused_field: "entry[body]")

    assert {:ok, updated} = Form.update(%{event: "apply_remote_field_changes", changes: changes}, socket)
    assert updated.assigns.form[:title].value == "Remote title"
    assert updated.assigns.form[:body].value == "<p>Local draft</p>"

    assert updated.assigns.held_remote == %{
             body: %{field: :body, value: "<p>Older remote body</p>", assoc?: false, clock: {1, "remote"}}
           }
  end

  # Two editors who send the same field at once each get the other's value.
  # The clock (count, then tab) picks one, the same for both.
  test "of two changes to one field, the newer clock wins and an older one is dropped" do
    newer = [%{field: :title, value: "Newer", assoc?: false, clock: {2, "a"}}]
    older = [%{field: :title, value: "Older", assoc?: false, clock: {1, "z"}}]
    tie = [%{field: :title, value: "Tie, lower tab", assoc?: false, clock: {2, "0"}}]

    assert {:ok, socket} = Form.update(%{event: "apply_remote_field_changes", changes: newer}, socket())
    assert {:ok, socket} = Form.update(%{event: "apply_remote_field_changes", changes: older}, socket)
    assert {:ok, socket} = Form.update(%{event: "apply_remote_field_changes", changes: tie}, socket)
    assert socket.assigns.form[:title].value == "Newer"
  end

  # A hybrid logical clock: the wall clock in milliseconds, or one past the
  # newest clock known for the field when that is ahead of it.
  test "a change this editor ships is stamped with the time, or past the newest clock it knows" do
    Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.entry("field_sync", Entry, "entry-1"))
    tab = BrandoAdmin.Presence.tab()
    before = System.os_time(:millisecond)

    socket = socket(unshipped_fields: MapSet.new([:body]), field_clocks: %{body: {4, "other"}})
    assert {:ok, _} = Form.update(%{event: "ship_field_changes"}, socket)
    assert_receive {:fields_shipped, %{changes: [%{field: :body, clock: {n, ^tab}}]}}
    assert n >= before

    ahead = before + 60_000
    socket = socket(unshipped_fields: MapSet.new([:body]), field_clocks: %{body: {ahead, "other"}})
    assert {:ok, _} = Form.update(%{event: "ship_field_changes"}, socket)
    assert_receive {:fields_shipped, %{changes: [%{field: :body, clock: {n, ^tab}}]}}
    assert n == ahead + 1
  end

  # A joining tab is sent the clocks with the values, also when there are no
  # values, and keeps the newest of each.
  test "clocks sent to a joining tab are merged, newest kept" do
    socket = socket(field_clocks: %{title: {9, "a"}, body: {2, "a"}})
    clocks = %{title: {3, "b"}, body: {5, "b"}, caption: {1, "b"}}

    assert {:ok, updated} = Form.update(%{event: "apply_remote_field_changes", changes: [], clocks: clocks}, socket)
    assert updated.assigns.field_clocks == %{title: {9, "a"}, body: {5, "b"}, caption: {1, "b"}}
  end

  test "a remote value equal to the saved one replaces what the editor's browser sent" do
    entry = %Entry{id: "entry-1", title: "Stored title", body: "<p>Stored body</p>", caption: "<p>Caption</p>"}
    changeset = Changeset.cast(entry, %{"title" => "Typed title"}, [:title])
    socket = socket(form: Component.to_form(changeset, as: "entry"))
    changes = [%{field: :title, value: "Stored title", assoc?: false, clock: {1, "remote"}}]

    assert {:ok, updated} = Form.update(%{event: "apply_remote_field_changes", changes: changes}, socket)
    assert updated.assigns.form[:title].value == "Stored title"
  end

  test "a field changed back to its saved value ships, and the editors are told nothing is pending" do
    Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.entry("field_sync", Entry, "entry-1"))
    Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.entry("dirty_fields", Entry, "entry-1"))

    # The editors got "Shipped title" from us; the form holds the stored title again.
    socket =
      socket(
        synced_values: %{title: "Shipped title"},
        unshipped_fields: MapSet.new([:title, :body]),
        dirty_fields: ["entry[body]", "entry[title]"]
      )

    assert {:ok, updated} = Form.update(%{event: "ship_field_changes"}, socket)

    assert_receive {:fields_shipped, %{changes: changes, user_id: 1}}

    tab = BrandoAdmin.Presence.tab()

    assert [
             %{field: :body, value: "<p>Local draft</p>", assoc?: false, clock: {_, ^tab}},
             %{field: :title, value: "Stored title", assoc?: false, clock: {_, ^tab}}
           ] = Enum.sort_by(changes, & &1.field)

    assert_receive {:dirty_fields, [], 1}
    assert updated.assigns.dirty_fields == []
  end
end
