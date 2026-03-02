defmodule Brando.Villain.Blocks.GalleryBlock do
  @moduledoc false
  use Brando.Villain.Block,
    type: "gallery"

  defmodule Data do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "GalleryBlockData",
      singular: "gallery_block_data",
      plural: "gallery_block_datas",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded
    identifier false
    persist_identifier false

    attributes do
      attribute :class, :string
      attribute :lightbox, :boolean, default: false

      attribute :placeholder, :enum,
        values: [:svg, :dominant_color, :dominant_color_faded, :micro, :none],
        default: :dominant_color

      attribute :display, :enum,
        values: [:list, :grid],
        default: :grid

      attribute :type, :enum,
        values: [:gallery, :slider, :slideshow],
        default: :gallery

      attribute :formats, {:array, Ecto.Enum}, values: [:original, :jpg, :png, :gif, :webp, :avif, :svg]
    end

    relations do
      relation :gallery_object_overrides, :embeds_many, module: Brando.Villain.Blocks.GalleryObjectOverride
    end
  end

  def apply_ref(Brando.Villain.Blocks.MediaBlock, ref_src, ref_target_changeset) do
    # in order to not overwrite the chosen media block, we have to get the media
    # block template and merge against this instead
    tpl_src = ref_src.data.data.template_gallery

    # Get the current data from the ref changeset - it might be a struct or changeset
    current_data = Ecto.Changeset.get_field(ref_target_changeset, :data)

    # Ensure we have a changeset for the data
    data_changeset =
      case current_data do
        %Ecto.Changeset{} = cs -> cs
        data -> Ecto.Changeset.change(data)
      end

    # Get the current block data and merge with template data
    current_block_data = Ecto.Changeset.get_field(data_changeset, :data)
    merged_data = Map.merge(Map.from_struct(current_block_data), Map.from_struct(tpl_src))

    # Update the data changeset
    updated_data_changeset = Ecto.Changeset.put_change(data_changeset, :data, merged_data)

    # Apply the data changeset to get the final block struct
    updated_block = Ecto.Changeset.apply_changes(updated_data_changeset)

    # Return the updated ref changeset with the applied block data
    Ecto.Changeset.put_change(ref_target_changeset, :data, updated_block)
  end

  def apply_ref(_, ref_src, ref_target_changeset) do
    # Get the current data from the ref changeset - it might be a struct or changeset
    current_data = Ecto.Changeset.get_field(ref_target_changeset, :data)

    # Ensure we have a changeset for the data
    data_changeset =
      case current_data do
        %Ecto.Changeset{} = cs -> cs
        data -> Ecto.Changeset.change(data)
      end

    # Extract the source attributes and get current block data
    src_attrs = Map.from_struct(ref_src.data.data)
    current_block_data = Ecto.Changeset.get_field(data_changeset, :data)

    # Merge the attributes
    merged_data = Map.merge(Map.from_struct(current_block_data), src_attrs)

    # Update the data changeset
    updated_data_changeset = Ecto.Changeset.put_change(data_changeset, :data, merged_data)

    # Apply the data changeset to get the final block struct
    updated_block = Ecto.Changeset.apply_changes(updated_data_changeset)

    # Return the updated ref changeset with the applied block data
    Ecto.Changeset.put_change(ref_target_changeset, :data, updated_block)
  end
end
