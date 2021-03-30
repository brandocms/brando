defmodule Brando.Image do
  @moduledoc """
  Ecto schema for the Image schema
  and helper functions for dealing with the schema.
  """

  use Brando.Blueprint,
    application: "Brando",
    domain: "Images",
    schema: "Image",
    singular: "image",
    plural: "images"

  trait Brando.Trait.Creator
  trait Brando.Trait.Sequenced
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Timestamped

  identifier "{{ entry.id }}"

  attributes do
    attribute :image, :image, :db
  end

  relations do
    relation :image_series, :belongs_to, module: Brando.ImageSeries
  end

  @derive {Jason.Encoder,
           only: [
             :id,
             :image,
             :creator,
             :creator_id,
             :image_series_id,
             :image_series,
             :sequence,
             :inserted_at,
             :updated_at,
             :deleted_at
           ]}
end
