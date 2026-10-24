defmodule Brando.Villain.Blocks.CaptionTest do
  # A video or picture block's caption (`title`) is rich text. An editor
  # emptied sends `<p></p>`, which is no caption: stored as nil, the
  # placement takes the asset's own again. Markup the rich-text editor
  # can't make is stripped, as gallery captions are.
  use ExUnit.Case, async: true

  alias Brando.Villain.Blocks.PictureBlock
  alias Brando.Villain.Blocks.VideoBlock

  defp caption(block, title) do
    block
    |> struct()
    |> block.changeset(%{"type" => block.__block_type__(), "data" => %{"title" => title}})
    |> Ecto.Changeset.apply_changes()
    |> Map.fetch!(:data)
    |> Map.fetch!(:title)
  end

  for block <- [VideoBlock, PictureBlock] do
    test "#{inspect(block)}: an emptied caption is no caption" do
      assert caption(unquote(block), "<p></p>") == nil
      assert caption(unquote(block), "<p><br></p>") == nil
      assert caption(unquote(block), "") == nil
    end

    test "#{inspect(block)}: a caption keeps its markup, without what the editor can't make" do
      assert caption(unquote(block), "<p><strong>Tour</strong> film</p>") == "<p><strong>Tour</strong> film</p>"
      refute caption(unquote(block), ~s{<p>Tour<img src=x onerror="alert(1)"></p>}) =~ "onerror"
    end
  end
end
