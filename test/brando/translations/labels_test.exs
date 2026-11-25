defmodule Brando.Translations.LabelsTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.Forms.{Input, Subform}
  alias Brando.Translations.Labels

  defmodule Article do
    def __naming__, do: %{domain: "Test", schema: "Article"}
    def __modules__, do: %{gettext: Brando.Gettext}

    def __form__ do
      fields = [
        %Input{name: :title, opts: [label: "Article title"]},
        %Subform{name: :items, sub_fields: [%Input{name: :title, opts: [label: "Item title"]}]},
        %Subform{name: :notes, sub_fields: [%Input{name: :title, opts: [label: "Note title"]}]}
      ]

      %{tabs: [%{fields: [%{fields: fields}]}]}
    end
  end

  test "entry and subform inputs with the same name keep their own labels" do
    labels = Labels.field_labels(Article)
    label = fn path -> path |> Labels.target(%{}) |> Labels.label(labels) end

    assert label.("title") == "Article title"
    assert label.("items/one/title") == "Items › Item title"
    assert label.("notes/two/title") == "Notes › Note title"
    assert label.("extras/three/title") == "Extras › Title"
  end
end
