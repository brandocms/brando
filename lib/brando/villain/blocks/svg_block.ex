defmodule Brando.Villain.Blocks.SvgBlock do
  @moduledoc false
  use Brando.Villain.Block,
    type: "svg"

  defmodule Data do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "SvgBlockData",
      singular: "svg_block_data",
      plural: "svg_block_datas",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded
    identifier false
    persist_identifier false

    attributes do
      attribute :class, :text
      attribute :code, :text
    end
  end

  def protected_attrs do
    [:code]
  end

  def apply_ref(Brando.Villain.Blocks.MediaBlock, ref_src, ref_target_changeset) do
    # in order to not overwrite the chosen media block, we have to get the media
    # block template and merge against this instead
    tpl_src = ref_src.data.data.template_svg
    protected_attrs = __MODULE__.protected_attrs()
    
    # Get the source attributes, excluding protected ones
    src_attrs = Map.from_struct(tpl_src)
    overwritten_attrs = Map.keys(src_attrs) -- protected_attrs
    new_attrs = Map.take(src_attrs, overwritten_attrs)
    
    # Get the current data from the changeset
    current_data = Ecto.Changeset.get_field(ref_target_changeset, :data)
    
    # Get the current block data
    current_block_data = 
      case current_data do
        %Ecto.Changeset{} = cs -> Ecto.Changeset.get_field(cs, :data)
        data -> data.data
      end
    
    # Merge the attributes
    merged_data = Map.merge(Map.from_struct(current_block_data), new_attrs)
    
    # Create updated data changeset
    data_changeset = 
      case current_data do
        %Ecto.Changeset{} = cs -> cs
        data -> Ecto.Changeset.change(data)
      end
    
    updated_data_changeset = Ecto.Changeset.put_change(data_changeset, :data, merged_data)
    
    # Apply the data changeset to get the final block struct
    updated_block = Ecto.Changeset.apply_changes(updated_data_changeset)
    
    # Return the updated ref changeset with the applied block data
    Ecto.Changeset.put_change(ref_target_changeset, :data, updated_block)
  end

  def apply_ref(_, ref_src, ref_target_changeset) do
    protected_attrs = __MODULE__.protected_attrs()
    
    # Get the source attributes, excluding protected ones
    src_attrs = Map.from_struct(ref_src.data.data)
    overwritten_attrs = Map.keys(src_attrs) -- protected_attrs
    new_attrs = Map.take(src_attrs, overwritten_attrs)
    
    # Get the current data from the changeset
    current_data = Ecto.Changeset.get_field(ref_target_changeset, :data)
    
    # Get the current block data
    current_block_data = 
      case current_data do
        %Ecto.Changeset{} = cs -> Ecto.Changeset.get_field(cs, :data)
        data -> data.data
      end
    
    # Merge the attributes
    merged_data = Map.merge(Map.from_struct(current_block_data), new_attrs)
    
    # Create updated data changeset
    data_changeset = 
      case current_data do
        %Ecto.Changeset{} = cs -> cs
        data -> Ecto.Changeset.change(data)
      end
    
    updated_data_changeset = Ecto.Changeset.put_change(data_changeset, :data, merged_data)
    
    # Apply the data changeset to get the final block struct
    updated_block = Ecto.Changeset.apply_changes(updated_data_changeset)
    
    # Return the updated ref changeset with the applied block data
    Ecto.Changeset.put_change(ref_target_changeset, :data, updated_block)
  end
end
