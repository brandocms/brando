defmodule BrandoAdmin.Components.Form.BlockField.TextFillTest do
  # A block's texts by the paths of a synchronized translation's work items:
  # read from the block, written into its params so a cast gives the block
  # the new text.
  use Brando.ConnCase, async: true

  alias Brando.Content.Block
  alias Brando.Content.Ref
  alias Brando.Content.TableRow
  alias Brando.Content.Var
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias BrandoAdmin.Components.Form.BlockField.TextFill

  defp ref(id, name, data), do: %Ref{id: id, uid: "r#{id}", name: name, data: data}

  defp block do
    %Block{
      id: 1,
      uid: "root",
      type: :module,
      module_id: nil,
      identifier_metas: %{"7" => %{"title" => "Lenke"}},
      refs: [
        ref(11, "body", %Brando.Villain.Blocks.TextBlock{
          type: "text",
          data: %Brando.Villain.Blocks.TextBlock.Data{text: "<p>Hei</p>"}
        }),
        ref(12, "photo", %Brando.Villain.Blocks.PictureBlock{
          type: "picture",
          data: %Brando.Villain.Blocks.PictureBlock.Data{alt: "Et hus", title: "Huset"}
        })
      ],
      vars: [%Var{id: 21, key: "caption", type: :string, value: "Bildetekst"}],
      table_rows: [%TableRow{id: 31, sync_uid: "row1", vars: [%Var{id: 32, key: "cell", type: :text, value: "Celle"}]}],
      block_identifiers: [],
      children: [
        %Block{
          id: 2,
          uid: "child",
          type: :module,
          refs: [
            ref(13, "body", %Brando.Villain.Blocks.TextBlock{
              type: "text",
              data: %Brando.Villain.Blocks.TextBlock.Data{text: "Barn"}
            })
          ],
          vars: [],
          table_rows: [],
          block_identifiers: [],
          children: []
        }
      ]
    }
  end

  defp params(block), do: block |> Ecto.Changeset.change() |> Ops.snapshot_params()

  # onto the block, as the BlockField casts onto its saved rows
  defp cast(params), do: block() |> Block.recursive_block_changeset(params, 1) |> Ecto.Changeset.apply_changes()

  test "reads each kind of text" do
    block = block()
    assert TextFill.read(block, ["refs", "body", "text"]) == {:ok, "<p>Hei</p>"}
    assert TextFill.read(block, ["refs", "photo", "alt"]) == {:ok, "Et hus"}
    assert TextFill.read(block, ["vars", "caption", "value"]) == {:ok, "Bildetekst"}
    assert TextFill.read(block, ["rows", "row1", "vars", "cell", "value"]) == {:ok, "Celle"}
    assert TextFill.read(block, ["identifier_metas", "7", "title"]) == {:ok, "Lenke"}
    assert TextFill.read(block, ["refs", "photo", "gallery", "image:1", "alt"]) == :error
    assert TextFill.read(block, ["refs", "missing", "text"]) == :error
  end

  test "puts a text where a cast of the params gives it to the block" do
    block = block()

    writes = [
      {["refs", "body", "text"], "<p>Hello</p>"},
      {["refs", "photo", "alt"], "A house"},
      {["vars", "caption", "value"], "Caption"},
      {["rows", "row1", "vars", "cell", "value"], "Cell"},
      {["identifier_metas", "7", "title"], "Link"}
    ]

    params =
      Enum.reduce(writes, params(block), fn {path, text}, params ->
        assert {:ok, params} = TextFill.put(params, block, path, text)
        params
      end)

    cast = cast(params)

    for {path, text} <- writes, do: assert(TextFill.read(cast, path) == {:ok, text})
  end

  test "finds a child block and its params by uid" do
    block = block()
    child = TextFill.find_block(block, "child")
    assert child.id == 2

    params =
      TextFill.update_block_params(params(block), "child", fn child_params ->
        {:ok, params} = TextFill.put(child_params, child, ["refs", "body", "text"], "Child")
        params
      end)

    assert cast(params) |> TextFill.find_block("child") |> TextFill.read(["refs", "body", "text"]) == {:ok, "Child"}
    assert TextFill.read(cast(params), ["refs", "body", "text"]) == {:ok, "<p>Hei</p>"}
  end

  test "a path it cannot write is an error" do
    block = block()
    assert TextFill.put(params(block), block, ["refs", "photo", "gallery", "image:1", "alt"], "x") == :error
    assert TextFill.put(params(block), block, ["vars", "missing", "value"], "x") == :error
  end
end
