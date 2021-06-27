defmodule Brando.ImageSeries do
  @moduledoc """
  Ecto schema for the Image Series schema
  and helper functions for dealing with the schema.
  """

  defmodule Trait.Slug do
    use Brando.Trait
    import Ecto.Changeset
    @changeset_phase :before_validate_required

    def changeset_mutator(_module, _config, changeset, _user, _opts) do
      Brando.Utils.Schema.put_slug(changeset, :name)
    end
  end

  defmodule Trait.CastImages do
    use Brando.Trait
    import Ecto.Changeset

    def changeset_mutator(_module, _config, changeset, user, _opts) do
      cast_assoc(changeset, :images,
        with: {Brando.Image, :changeset, [user, [image_db_config: get_field(changeset, :cfg)]]}
      )
    end
  end

  defmodule Trait.InheritConfiguration do
    use Brando.Trait
    import Ecto.Changeset

    def changeset_mutator(_, _, changeset, _, _opts) do
      case get_change(changeset, :cfg) do
        nil ->
          cat_id = get_field(changeset, :image_category_id)

          if !cat_id do
            raise "inherit_configuration => image_category_id === nil!"
          end

          slug = get_change(changeset, :slug)

          if slug do
            category = Brando.repo().get(Brando.ImageCategory, cat_id)
            new_upload_path = Path.join(Map.get(category.cfg, :upload_path), slug)
            cfg = Map.put(category.cfg, :upload_path, new_upload_path)
            put_change(changeset, :cfg, cfg)
          else
            changeset
          end

        _ ->
          changeset
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
          _user,
          _opts
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

    def changeset_mutator(_, _, changeset, _, _opts) do
      changeset
    end
  end

  use Brando.Blueprint,
    application: "Brando",
    domain: "Images",
    schema: "ImageSeries",
    singular: "image_series",
    plural: "image_series"

  import Ecto.Query

  table "images_series"

  trait Brando.Trait.Creator
  trait Brando.Trait.Sequenced
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Timestamped
  trait __MODULE__.Trait.Slug
  trait __MODULE__.Trait.InheritConfiguration
  trait __MODULE__.Trait.CastImages

  identifier "{{ entry.name }}"

  attributes do
    attribute :name, :string, required: true

    attribute :slug, :slug,
      from: :name,
      required: true,
      unique: [prevent_collision: &Brando.ImageSeries.filter_current_category/2]

    attribute :credits, :string
    attribute :cfg, Brando.Type.ImageConfig
  end

  relations do
    relation :image_category, :belongs_to, module: Brando.ImageCategory, required: true
    relation :images, :has_many, module: Brando.Image
  end

  @doc """
  Filter used in `avoid_field_collision` to ensure we are only checking slugs
  from the same category.
  """
  def filter_current_category(module, changeset) do
    from m in module,
      where: m.image_category_id == ^get_field(changeset, :image_category_id)
  end
end
