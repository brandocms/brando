defmodule BrandoAdmin.Components.Form.BlockHelpersTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]

  alias Brando.Villain.Blocks.PictureBlock
  alias BrandoAdmin.Components.Form.Block
  alias Ecto.Changeset

  defp picture_block_form(data_attrs, changes \\ %{}) do
    block = %PictureBlock{type: "picture", data: struct(PictureBlock.Data, data_attrs)}

    changeset =
      if changes == %{} do
        Changeset.change(block)
      else
        PictureBlock.changeset(block, %{"data" => changes})
      end

    to_form(changeset, as: :block)
  end

  describe "current_block_data_map/3" do
    test "returns block data as a plain map" do
      form = picture_block_form(%{title: "A title", alt: "Alt text"})
      result = Block.current_block_data_map(form)

      refute is_struct(result)
      assert result.title == "A title"
      assert result.alt == "Alt text"
    end

    test "applies pending changeset changes" do
      form = picture_block_form(%{title: "Original"}, %{title: "Edited"})
      assert Block.current_block_data_map(form).title == "Edited"
    end

    test "restricts to given fields" do
      form = picture_block_form(%{title: "A title", alt: "Alt text"})
      result = Block.current_block_data_map(form, [:title])

      assert result == %{title: "A title"}
    end

    test "merges overrides last" do
      form = picture_block_form(%{title: "A title", alt: "Alt"})
      result = Block.current_block_data_map(form, [:title, :alt], %{alt: nil})

      assert result == %{title: "A title", alt: nil}
    end
  end

  describe "resolve_ref_association/4" do
    defmodule Ref do
      use Ecto.Schema

      embedded_schema do
        field :image_id, :integer
        field :name, :string
      end
    end

    defp ref_form(attrs) do
      struct(Ref, attrs)
      |> Changeset.change()
      |> to_form(as: :ref)
    end

    test "returns nil for nil form" do
      assert Block.resolve_ref_association(nil, :image, :image_id, fn _ -> raise "no fetch" end) == nil
    end

    test "fetches by FK when association field is nil" do
      form = ref_form(%{image_id: 42})

      fetched =
        Block.resolve_ref_association(form, :name, :image_id, fn 42 -> {:ok, %{id: 42}} end)

      assert fetched == %{id: 42}
    end

    test "returns nil when FK is nil" do
      form = ref_form(%{image_id: nil})
      assert Block.resolve_ref_association(form, :name, :image_id, fn _ -> raise "no fetch" end) == nil
    end

    test "returns nil when fetch fails" do
      form = ref_form(%{image_id: 42})
      assert Block.resolve_ref_association(form, :name, :image_id, fn _ -> {:error, :nope} end) == nil
    end

    test "prefers the preloaded association value over fetching" do
      form = ref_form(%{image_id: 42, name: "preloaded"})

      assert Block.resolve_ref_association(form, :name, :image_id, fn _ -> raise "no fetch" end) ==
               "preloaded"
    end
  end
end
