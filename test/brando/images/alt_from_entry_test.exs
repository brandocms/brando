defmodule Brando.Images.AltFromEntryTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  alias Brando.Images.AltText

  defp image(config_target) do
    Brando.Repo.insert!(%Brando.Images.Image{
      path: "images/#{System.unique_integer([:positive])}.jpg",
      width: 10,
      height: 10,
      status: :processed,
      config_target: config_target,
      alt: %{}
    })
  end

  test "images of an asset with alt_from don't count as missing alt text" do
    target = "image:Brando.AltTextTest.Artwork:image"
    assert target in AltText.entry_alt_targets()

    from_entry = image(target)
    own = image("default")

    missing_ids = Enum.map(AltText.missing(), & &1.id)
    assert own.id in missing_ids
    refute from_entry.id in missing_ids

    assert AltText.alt_from_entry?(from_entry)
    refute AltText.alt_from_entry?(own)
  end
end
