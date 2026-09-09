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

  defp socket do
    changeset =
      %Entry{title: "Stored title", body: "<p>Stored body</p>", caption: "<p>Caption</p>"}
      |> Changeset.change(body: "<p>Local draft</p>")

    Component.assign(%Phoenix.LiveView.Socket{},
      schema: Entry,
      form: Component.to_form(changeset, as: "entry"),
      tiptap_epoch: "mounted-form"
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
end
