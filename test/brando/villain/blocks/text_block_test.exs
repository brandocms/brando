defmodule Brando.Villain.Blocks.TextBlockTest do
  use ExUnit.Case, async: true

  alias Brando.Villain.Blocks.TextBlock.Data
  alias Brando.Villain.Blocks.TextBlock.Style

  describe "Data.changeset/2" do
    test "casts embedded styles" do
      params = %{
        "text" => "<p>Hello</p>",
        "styles" => %{
          "0" => %{"element" => "p", "class" => "lede", "label" => "Lede", "icon" => "hero-circle-stack"},
          "1" => %{"element" => "h2", "class" => "display"},
          "2" => %{"element" => "span", "class" => "eyebrow", "label" => "Eyebrow"}
        },
        "sort_style_ids" => ["0", "1", "2"]
      }

      changeset = Data.changeset(%Data{}, params)

      assert changeset.valid?

      styles = Ecto.Changeset.get_change(changeset, :styles)
      assert length(styles) == 3

      [first, second, third] = Enum.map(styles, &Ecto.Changeset.apply_changes/1)

      assert first.element == "p"
      assert first.class == "lede"
      assert first.label == "Lede"
      assert first.icon == "hero-circle-stack"

      assert second.element == "h2"
      assert second.class == "display"
      assert second.label == nil

      assert third.element == "span"
      assert third.class == "eyebrow"
      assert third.label == "Eyebrow"
    end

    test "validates style entries" do
      params = %{
        "styles" => %{
          "0" => %{"element" => "script", "class" => "lede"},
          "1" => %{"element" => "p", "class" => "not valid"}
        },
        "sort_style_ids" => ["0", "1"]
      }

      changeset = Data.changeset(%Data{}, params)

      refute changeset.valid?

      styles = Ecto.Changeset.get_change(changeset, :styles)

      assert Enum.any?(styles, fn cs ->
        not cs.valid?
      end)
    end
  end

  test "default_styles/0 provides a lede paragraph style preset" do
    [style] = Data.default_styles()
    assert %Style{} = style
    assert style.element == "p"
    assert style.class == "lede"
    assert style.label == "Lede"
    assert style.icon == "hero-circle-stack"
  end

  describe "Data.normalize_styles/1" do
    test "converts Style structs to maps for JSON encoding" do
      styles = [
        %Style{element: "p", class: "lede", label: "Lede", icon: "hero-circle-stack"},
        %Style{element: "h2", class: "display"}
      ]

      assert Data.normalize_styles(styles) == [
               %{"element" => "p", "class" => "lede", "label" => "Lede", "icon" => "hero-circle-stack"},
               %{"element" => "h2", "class" => "display"}
             ]
    end

    test "deduplicates by element+class" do
      styles = [
        %Style{element: "p", class: "lede", label: "First"},
        %Style{element: "p", class: "lede", label: "Duplicate"}
      ]

      assert Data.normalize_styles(styles) == [
               %{"element" => "p", "class" => "lede", "label" => "First"}
             ]
    end
  end
end
