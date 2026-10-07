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
          synced_values: %{}
        ],
        assigns
      )
    )
  end

  test "remote field messages apply their list of changes without replacing untouched rich text" do
    changes = [%{field: :title, value: "Remote title", assoc?: false}]

    assert {:ok, updated} = Form.update(%{event: "apply_remote_field_changes", changes: changes}, socket())
    assert updated.assigns.form[:title].value == "Remote title"
    assert updated.assigns.form[:body].value == "<p>Local draft</p>"

    events = Phoenix.LiveView.Utils.get_push_events(updated)
    assert ["b:component:remount", %{skip_rich_text: true}] in events
    refute Enum.any?(events, fn [event, _] -> event == "b:tiptap:update" end)
  end

  test "remote rich-text changes target only their own editor, including an empty replacement" do
    changes = [
      %{field: :title, value: "Remote title", assoc?: false},
      %{field: :body, value: "", assoc?: false}
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

  test "a remote change leaves the field being typed in alone" do
    changes = [
      %{field: :title, value: "Remote title", assoc?: false},
      %{field: :body, value: "<p>Older remote body</p>", assoc?: false}
    ]

    socket = socket(focused_field: "entry[body]")

    assert {:ok, updated} = Form.update(%{event: "apply_remote_field_changes", changes: changes}, socket)
    assert updated.assigns.form[:title].value == "Remote title"
    assert updated.assigns.form[:body].value == "<p>Local draft</p>"
    assert updated.assigns.synced_values == %{title: "Remote title"}
  end

  test "a field changed back to its saved value ships, and the editors are told nothing is pending" do
    Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.entry("field_sync", Entry, "entry-1"))
    Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.entry("dirty_fields", Entry, "entry-1"))

    # The editors got "Shipped title" from us; the form holds the stored title again.
    socket = socket(synced_values: %{title: "Shipped title"}, dirty_fields: ["entry[body]", "entry[title]"])

    assert {:ok, updated} = Form.update(%{event: "ship_field_changes"}, socket)

    assert_receive {:fields_shipped, %{changes: changes, user_id: 1}}

    assert Enum.sort_by(changes, & &1.field) == [
             %{field: :body, value: "<p>Local draft</p>", assoc?: false},
             %{field: :title, value: "Stored title", assoc?: false}
           ]

    assert_receive {:dirty_fields, [], 1}
    assert updated.assigns.dirty_fields == []
  end
end
