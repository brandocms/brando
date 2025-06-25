defmodule Brando.Galleries.GalleryObject do
  @moduledoc """
  Gallery <-> Image/Video join table
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Galleries",
    schema: "GalleryObject",
    singular: "gallery_object",
    plural: "gallery_objects",
    gettext_module: Brando.Gettext

  alias Brando.Galleries.Gallery
  alias Brando.Images.Image
  alias Brando.Videos.Video

  trait Brando.Trait.Creator
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped

  identifier false
  persist_identifier false

  relations do
    relation :gallery, :belongs_to, module: Gallery
    relation :image, :belongs_to, module: Image
    relation :video, :belongs_to, module: Video
  end
end
