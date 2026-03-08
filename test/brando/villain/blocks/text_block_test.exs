defmodule Brando.Villain.Blocks.TextBlockTest do
  use ExUnit.Case, async: true

  alias Brando.Villain.Blocks.TextBlock.Data

  describe "Data.changeset/2" do
    test "normalizes and deduplicates styles" do
      params = %{
        text: "<p>Hello</p>",
        styles: [
          %{element: " P ", class: " lede ", label: " Lede ", icon: " hero-circle "},
          %{"element" => "p", "class" => "lede", "label" => "Duplicate style"},
          %{element: "h2", class: "display"},
          %{element: "span", class: "eyebrow", label: "Eyebrow"}
        ]
      }

      changeset = Data.changeset(%Data{}, params)

      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :styles) == [
               %{
                 "element" => "p",
                 "class" => "lede",
                 "label" => "Lede",
                 "icon" => "hero-circle"
               },
               %{
                 "element" => "h2",
                 "class" => "display"
               },
               %{
                 "element" => "span",
                 "class" => "eyebrow",
                 "label" => "Eyebrow"
               }
             ]
    end

    test "adds errors for invalid style entries" do
      params = %{
        styles: [
          %{element: "p", class: "not valid"},
          %{element: "script", class: "lede"}
        ]
      }

      changeset = Data.changeset(%Data{}, params)

      refute changeset.valid?
      assert {"contains invalid entries at indexes: 0, 1", _} = changeset.errors[:styles]
    end
  end

  test "default_styles/0 provides a lede paragraph style preset" do
    assert Data.default_styles() == [
             %{
               "element" => "p",
               "class" => "lede",
               "label" => "Lede",
               "icon" => "hero-circle"
             }
           ]
  end
end
