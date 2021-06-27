defmodule Brando.Images.Image do
  defmodule Trait.PutDefaultFocal do
    use Brando.Trait
    import Ecto.Changeset

    def changeset_mutator(_module, _config, %{changes: %{focal: _}} = changeset, _user, _opts) do
      changeset
    end

    def changeset_mutator(_module, _config, %{data: %{focal: nil}} = changeset, _user, _opts) do
      put_change(changeset, :focal, %{x: 50, y: 50})
    end

    def changeset_mutator(_module, _config, %{changes: %{focal: nil}} = changeset, _user, _opts) do
      put_change(changeset, :focal, %{x: 50, y: 50})
    end

    def changeset_mutator(_module, _config, changeset, _user, _opts) do
      changeset
    end
  end

  @moduledoc """
  Embedded image
  """

  alias Brando.Images.Focal

  use Brando.Blueprint,
    application: "Brando",
    domain: "Images",
    schema: "Image",
    singular: "image",
    plural: "images"

  data_layer :embedded
  @primary_key false

  trait __MODULE__.Trait.PutDefaultFocal

  attributes do
    attribute :title, :text
    attribute :credits, :text
    attribute :alt, :text
    attribute :path, :text, required: true
    attribute :width, :integer
    attribute :height, :integer
    attribute :sizes, :map
    attribute :cdn, :boolean, default: false
    attribute :webp, :boolean, default: false
    attribute :dominant_color, :text
  end

  relations do
    relation :focal, :embeds_one, module: Focal
  end

  @derive {Jason.Encoder,
           only: [
             :title,
             :credits,
             :alt,
             :focal,
             :path,
             :sizes,
             :width,
             :height,
             :cdn,
             :webp,
             :dominant_color
           ]}
end
