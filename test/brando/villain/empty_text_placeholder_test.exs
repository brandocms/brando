defmodule Brando.Villain.EmptyTextPlaceholderTest do
  # A module's text and header refs can start empty, with a placeholder shown in
  # the editor instead of dummy text. The placeholder is part of the ref's data
  # but never of its text, and an empty ref renders nothing on the site.
  use ExUnit.Case, async: true

  alias Brando.Villain.Blocks.TextBlock.Data
  alias Brando.Villain.Parser

  test "a text ref's data keeps its placeholder" do
    changeset = Data.changeset(%Data{}, %{"text" => nil, "placeholder" => "Skriv teksten…"})

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :placeholder) == "Skriv teksten…"
    assert Ecto.Changeset.get_field(changeset, :text) == nil
  end

  test "an empty header renders nothing, not an empty heading" do
    assert Parser.header(%{text: nil, level: 2}, []) == ""
    assert Parser.header(%{text: "", level: 2}, []) == ""
    assert Parser.header(%{text: "Hei", level: 2}, []) |> IO.iodata_to_binary() == "<h2>Hei</h2>"
  end

  test "an empty text renders nothing, whatever its type" do
    assert Parser.text(%{text: nil, type: "lede"}, []) == ""
    assert Parser.text(%{text: "", type: "lede"}, []) == ""
    assert Parser.text(%{text: "<p>Hei</p>", type: "lede"}, []) == ~s(<div class="lede"><p>Hei</p></div>)
  end
end
