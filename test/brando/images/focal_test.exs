defmodule Brando.Images.FocalTest do
  use ExUnit.Case, async: true

  alias Brando.Images.Focal
  alias Brando.Images.Image

  defp figma_image, do: %Image{focal: %Focal{x: 50, y: 40, mode: :position}}

  defp focal(changeset), do: Ecto.Changeset.apply_changes(changeset).focal

  describe "an image's focal point mode" do
    test "the Figma import's own write keeps :position" do
      changeset = Image.changeset(%Image{focal: %Focal{}}, %{focal: %{x: 50, y: 40, mode: :position}}, :system)
      assert %Focal{x: 50, y: 40, mode: :position} = focal(changeset)
    end

    test "moving the point by hand sets it back to :center" do
      assert %Focal{x: 30, y: 40, mode: :center} =
               figma_image() |> Image.changeset(%{focal: %{x: 30, y: 40}}, :system) |> focal()

      # As the focal picker posts it
      assert %Focal{x: 50, y: 70, mode: :center} =
               figma_image() |> Image.changeset(%{"focal" => %{"x" => "50", "y" => "70"}}, :system) |> focal()
    end

    test "a form that posts the point unchanged keeps the mode" do
      assert %Focal{x: 50, y: 40, mode: :position} =
               figma_image() |> Image.changeset(%{"focal" => %{"x" => "50", "y" => "40"}}, :system) |> focal()
    end

    test "a point without a mode reads as :center" do
      assert %Focal{mode: :center} = Ecto.embedded_load(Focal, %{"x" => 50, "y" => 40}, :json)
      assert %Focal{mode: :position} = Ecto.embedded_load(Focal, %{"x" => 50, "y" => 40, "mode" => "position"}, :json)
    end
  end

  test "mode/1 reads stored points and plain maps, and anything else as :center" do
    assert Focal.mode(%Focal{mode: :position}) == :position
    assert Focal.mode(%{mode: "position"}) == :position
    assert Focal.mode(%{"mode" => "position"}) == :position
    assert Focal.mode(%{"mode" => :position}) == :position
    assert Focal.mode(%Focal{}) == :center
    assert Focal.mode(%{x: 50, y: 50}) == :center
    assert Focal.mode(%{mode: "sideways"}) == :center
    assert Focal.mode(%{mode: nil}) == :center
    assert Focal.mode(nil) == :center
  end

  test "the JSON of a focal point has its mode" do
    assert Jason.encode!(%Focal{x: 50, y: 40, mode: :position}) =~ ~s("mode":"position")
  end
end
