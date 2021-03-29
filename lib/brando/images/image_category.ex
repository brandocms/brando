defmodule Brando.ImageCategory do
  @moduledoc """
  Ecto schema for the Image Category schema
  and helper functions for dealing with the schema.
  """

  defmodule Trait.Slug do
    use Brando.Trait
    import Ecto.Changeset
    @changeset_phase :before_validate_required

    def changeset_mutator(_module, _config, changeset, _user) do
      Brando.Utils.Schema.put_slug(changeset, :name)
    end
  end

  defmodule Trait.DefaultConfig do
    use Brando.Trait
    import Ecto.Changeset

    def changeset_mutator(_module, _config, changeset, _user) do
      if get_change(changeset, :cfg, nil) do
        changeset
      else
        path_from_slug = get_change(changeset, :slug, "default")
        upload_path = Path.join(["images", "site", path_from_slug])

        default_config =
          Brando.Images
          |> Brando.config()
          |> Keyword.get(:default_config)
          |> Map.put(:upload_path, upload_path)

        put_change(changeset, :cfg, default_config)
      end
    end
  end

  defmodule Trait.ValidatePaths do
    use Brando.Trait
    import Ecto.Changeset

    def changeset_mutator(
          _module,
          _config,
          %Ecto.Changeset{data: %{id: _}, changes: %{slug: slug}} = changeset,
          _user
        ) do
      old_cfg = get_field(changeset, :cfg)
      split_path = Path.split(old_cfg.upload_path)

      new_path =
        split_path
        |> List.delete_at(Enum.count(split_path) - 1)
        |> Path.join()
        |> Path.join(slug)

      new_cfg = Map.put(old_cfg, :upload_path, new_path)

      put_change(changeset, :cfg, new_cfg)
    end

    def changeset_mutator(_, _, changeset, _) do
      changeset
    end
  end

  use Brando.Blueprint,
    application: "Brando",
    domain: "Images",
    schema: "ImageCategory",
    singular: "image_category",
    plural: "image_categories"

  table "images_categories"

  trait Brando.Trait.Creator
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Timestamps
  trait __MODULE__.Trait.Slug
  trait __MODULE__.Trait.DefaultConfig
  trait __MODULE__.Trait.ValidatePaths

  identifier "{{ entry.name }}"

  # @derive {Jason.Encoder,
  #          only: [
  #            :id,
  #            :name,
  #            :slug,
  #            :cfg,
  #            :creator,
  #            :creator_id,
  #            :image_series,
  #            :inserted_at,
  #            :updated_at,
  #            :deleted_at
  #          ]}

  attributes do
    attribute :name, :string, required: true
    attribute :slug, :slug, from: :name, required: true, unique: [prevent_collision: true]
    attribute :cfg, Brando.Type.ImageConfig
  end

  relations do
    relation :image_series, :has_many, module: Brando.ImageSeries
  end
end
