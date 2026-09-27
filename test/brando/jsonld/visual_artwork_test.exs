defmodule Brando.JSONLD.Schema.VisualArtworkTest do
  use ExUnit.Case, async: true

  alias Brando.JSONLD.Schema.VisualArtwork

  test "an artwork with its caption, by the site identity" do
    json =
      VisualArtwork.build(%{
        title: "The Reins",
        year: "2022",
        dimensions: "102 x 82 cm",
        medium: "Archival pigment print",
        image: nil
      })

    assert json.name == "The Reins"
    assert json.dateCreated == "2022"
    assert json.artMedium == "Archival pigment print"
    assert json.artist == %{"@id": "#{Brando.Utils.hostname()}/#identity"}
    assert json.height == %{"@type": "Distance", name: "102 cm"}
    assert json.width == %{"@type": "Distance", name: "82 cm"}
  end

  test "schema.org names win over the common ones" do
    json = VisualArtwork.build(%{name: "Torso", title: "Ignored", date_created: "2021", year: "1999"})
    assert {json.name, json.dateCreated} == {"Torso", "2021"}
  end

  test "dimensions it can't read are left out" do
    for dimensions <- ["Variable dimensions", "102 x 82", nil] do
      json = VisualArtwork.build(%{dimensions: dimensions})
      assert {json.height, json.width} == {nil, nil}
    end
  end
end
