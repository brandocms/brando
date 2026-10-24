defmodule Brando.Villain.Blocks.CaptionTest do
  # A video or picture block's caption (`title`) is rich text. An editor
  # emptied sends `<p></p>`, which is no caption: stored as nil, the
  # placement takes the asset's own again. Markup the rich-text editor
  # can't make is stripped, as gallery captions are.
  use ExUnit.Case, async: true

  alias Brando.Content.Proposals.RefConfig
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

  # A setting of each block, to change while the caption stays as stored
  @settings %{VideoBlock => {"autoplay", "true"}, PictureBlock => {"alt", "Alt"}}

  for block <- [VideoBlock, PictureBlock] do
    test "#{inspect(block)}: an emptied caption is no caption" do
      assert caption(unquote(block), "<p></p>") == nil
      assert caption(unquote(block), "<p><br></p>") == nil
      assert caption(unquote(block), ~s(<p style="text-align: center;"></p>)) == nil
      assert caption(unquote(block), "") == nil
    end

    test "#{inspect(block)}: a stored empty caption is cleaned when the data is saved" do
      block = unquote(block)
      {setting, value} = Map.fetch!(@settings, block)
      stored = struct(block, data: struct(Module.concat(block, Data), title: "<p></p>"))

      data =
        stored
        |> block.changeset(%{"type" => block.__block_type__(), "data" => %{"title" => "<p></p>", setting => value}})
        |> Ecto.Changeset.apply_changes()
        |> Map.fetch!(:data)

      assert data.title == nil
    end

    test "#{inspect(block)}: a caption set by a proposal is normalized" do
      block = unquote(block)
      type = block.__block_type__()

      ref =
        Ecto.Changeset.change(%Brando.Content.Ref{
          data: struct(block, type: type, data: struct(Module.concat(block, Data)))
        })

      title = fn config ->
        ref |> RefConfig.put(config) |> Ecto.Changeset.get_field(:data) |> Map.fetch!(:data) |> Map.fetch!(:title)
      end

      assert title.(%{"title" => "<p></p>"}) == nil
      refute title.(%{"title" => ~s{<p>Tour<img src=x onerror="alert(1)"></p>}}) =~ "onerror"
      assert title.(%{"title" => "<p><em>Tour</em></p>"}) == "<p><em>Tour</em></p>"
    end

    test "#{inspect(block)}: a caption keeps its markup, without what the editor can't make" do
      assert caption(unquote(block), "<p><strong>Tour</strong> film</p>") == "<p><strong>Tour</strong> film</p>"
      refute caption(unquote(block), ~s{<p>Tour<img src=x onerror="alert(1)"></p>}) =~ "onerror"
    end
  end
end
