defmodule Brando.Images.GalleryImage do
  @moduledoc """
  Gallery <-> Image join table
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Images",
    schema: "GalleryImage",
    singular: "gallery_image",
    plural: "gallery_images",
    gettext_module: Brando.Gettext

  alias Brando.Images.Gallery
  alias Brando.Images.Image

  trait Brando.Trait.Creator
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped

  identifier "{{ entry.id }}"

  attributes do
  end

  relations do
    relation :gallery, :belongs_to, module: Gallery
    relation :image, :belongs_to, module: Image
  end
end
