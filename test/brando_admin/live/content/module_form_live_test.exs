defmodule BrandoAdmin.Live.Content.ModuleFormLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]

  alias Ecto.Changeset
  alias Brando.Content.Module
  alias Brando.Villain.Blocks.TextBlock
  alias BrandoAdmin.Content.ModuleFormLive

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
end
