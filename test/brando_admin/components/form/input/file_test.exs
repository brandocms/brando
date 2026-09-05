defmodule BrandoAdmin.Components.Form.Input.FileTest do
  use Brando.ConnCase, async: false

  alias Brando.Files.File
  alias Brando.Repo
  alias BrandoAdmin.Components.Form.Input
  alias Ecto.Changeset

  test "a picker association change still supplies its file before the FK is persisted" do
    file = Repo.insert!(%File{filename: "picked.pdf", filesize: 1})

    form =
      %Brando.Content.Ref{file: nil}
      |> Changeset.change()
      |> Changeset.put_assoc(:file, file)
      |> Phoenix.Component.to_form(as: :ref)

    {:ok, socket} = Input.File.mount(%Phoenix.LiveView.Socket{})
    {:ok, socket} = Input.File.update(%{field: form[:file], opts: [], id: "file-input"}, socket)
    assert socket.assigns.file == file
    assert socket.assigns.file_id == file.id
  end

  test "recovered file FKs replace or clear a stale preloaded association" do
    original = Repo.insert!(%File{filename: "original.pdf", filesize: 1})
    replacement = Repo.insert!(%File{filename: "replacement.pdf", filesize: 2})
    saved = %Brando.Content.Ref{file: original, file_id: original.id}

    for {id, expected} <- [{replacement.id, replacement}, {nil, nil}] do
      form = saved |> Changeset.change(%{file_id: id}) |> Phoenix.Component.to_form(as: :ref)
      {:ok, socket} = Input.File.mount(%Phoenix.LiveView.Socket{})
      {:ok, socket} = Input.File.update(%{field: form[:file], opts: [], id: "file-input"}, socket)
      assert socket.assigns.file == expected
      assert socket.assigns.file_id == id
    end
  end
end
