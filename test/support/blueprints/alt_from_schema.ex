defmodule Brando.AltTextTest.Artwork do
  @moduledoc false
  # An image asset whose alt text the site takes from the entry's title.
  use Brando.Blueprint,
    application: "Brando",
    domain: "AltTextTest",
    schema: "Artwork",
    singular: "artwork",
    plural: "artworks",
    gettext_module: Brando.Gettext

  attributes do
    attribute :title, :string
  end

  assets do
    asset :image, :image, alt_from: :title, cfg: :default
  end
end
