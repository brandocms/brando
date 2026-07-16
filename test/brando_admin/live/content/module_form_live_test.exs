defmodule BrandoAdmin.Live.Content.ModuleFormLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]

  alias Brando.Content.Ref
  alias Brando.Content.Module
  alias Brando.Content.Var
  alias Brando.Content.Var.Option
  alias Brando.Villain.Blocks.TextBlock
  alias BrandoAdmin.Content.ModuleFormLive
  alias Ecto.Changeset

  test "create_ref/2 initializes text refs with default styles preset" do
    changeset =
      %Module{}
      |> Changeset.change()
      |> Changeset.put_assoc(:refs, [])

    form = to_form(changeset, [])
    socket = Phoenix.Component.assign(%Phoenix.LiveView.Socket{}, :form, form)

    assert {:noreply, updated_socket} =
             ModuleFormLive.handle_event("create_ref", %{"type" => "text"}, socket)

    updated_changeset = updated_socket.assigns.form.source
    [new_ref | _] = Changeset.get_assoc(updated_changeset, :refs)
    text_block = Changeset.get_field(new_ref, :data)

    assert text_block.type == "text"
    assert text_block.data.styles == TextBlock.Data.default_styles()
  end

  test "create_var/2 uses a readable, unique key and inserts an association changeset" do
    existing_var = Changeset.change(%Var{key: "text", label: "Existing", type: :text})

    socket =
      %Module{}
      |> Changeset.change()
      |> Changeset.put_assoc(:vars, [existing_var])
      |> form_socket()

    assert {:noreply, updated_socket} =
             ModuleFormLive.handle_event("create_var", %{"type" => "text"}, socket)

    [new_var, _existing_var] = Changeset.get_assoc(updated_socket.assigns.form.source, :vars)

    assert new_var.action == :insert
    assert Changeset.get_field(new_var, :key) == "text_2"
    assert Changeset.get_field(new_var, :label) == "Text"
    assert Changeset.get_field(new_var, :type) == :text
  end

  test "duplicate_var/2 preserves pending edits while resetting persisted identity" do
    persisted_var =
      %Var{
        id: 42,
        module_id: 7,
        sequence: 3,
        key: "theme",
        label: "Theme",
        type: :select,
        options: [%Option{label: "Dark", value: "dark"}]
      }
      |> Ecto.put_meta(state: :loaded)
      |> Changeset.change(%{label: "Pending theme"})

    socket =
      %Module{}
      |> Changeset.change()
      |> Changeset.put_assoc(:vars, [persisted_var])
      |> form_socket()

    assert {:noreply, updated_socket} =
             ModuleFormLive.handle_event("duplicate_var", %{"index" => "0"}, socket)

    [duplicate, original] = Changeset.get_assoc(updated_socket.assigns.form.source, :vars)
    duplicate_var = Changeset.apply_changes(duplicate)

    assert duplicate.action == :insert
    assert duplicate_var.id == nil
    assert duplicate_var.module_id == nil
    assert duplicate_var.sequence == nil
    assert duplicate_var.key == "theme_copy"
    assert duplicate_var.label == "Pending theme"
    assert [%Option{label: "Dark", value: "dark"}] = duplicate_var.options
    assert Changeset.get_field(original, :id) == 42
  end

  test "duplicate_ref/2 copies the current ref data with a new name and uid" do
    text_data = %TextBlock{data: %TextBlock.Data{text: "Pending text"}}

    persisted_ref =
      %Ref{id: 21, name: "intro", uid: "original-ref", data: text_data}
      |> Ecto.put_meta(state: :loaded)
      |> Changeset.change(%{description: "Pending description"})

    socket =
      %Module{}
      |> Changeset.change()
      |> Changeset.put_assoc(:refs, [persisted_ref])
      |> form_socket()

    assert {:noreply, updated_socket} =
             ModuleFormLive.handle_event("duplicate_ref", %{"index" => "0"}, socket)

    [duplicate, original] = Changeset.get_assoc(updated_socket.assigns.form.source, :refs)

    assert duplicate.action == :insert
    assert Changeset.get_field(duplicate, :id) == nil
    assert Changeset.get_field(duplicate, :name) == "intro_copy"
    assert Changeset.get_field(duplicate, :uid) != "original-ref"
    assert Changeset.get_field(duplicate, :description) == "Pending description"
    assert Changeset.get_field(duplicate, :data).data.text == "Pending text"
    assert Changeset.get_field(original, :id) == 21
  end

  test "refs persist the association position supplied by sortable module forms" do
    ref = %Ref{name: "intro", uid: "sortable-ref", data: %TextBlock{data: %TextBlock.Data{}}}

    changeset = Ref.changeset(ref, %{}, :system, 3, [])

    assert Changeset.get_change(changeset, :sequence) == 3
  end

  test "delete handlers target form indices rather than mutable keys" do
    vars = [
      Changeset.change(%Var{key: "first", label: "First", type: :string}),
      Changeset.change(%Var{key: "second", label: "Second", type: :string})
    ]

    socket =
      %Module{}
      |> Changeset.change()
      |> Changeset.put_assoc(:vars, vars)
      |> form_socket()

    assert {:noreply, updated_socket} =
             ModuleFormLive.handle_event("delete_var", %{"index" => "0"}, socket)

    assert [remaining] = Changeset.get_assoc(updated_socket.assigns.form.source, :vars)
    assert Changeset.get_field(remaining, :key) == "second"
  end

  defp form_socket(changeset) do
    Phoenix.Component.assign(%Phoenix.LiveView.Socket{}, :form, to_form(changeset, []))
  end
end
