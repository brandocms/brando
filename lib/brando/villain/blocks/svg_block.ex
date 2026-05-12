defmodule Brando.Villain.Blocks.SvgBlock do
  @moduledoc false
  use Brando.Villain.Block, type: "svg"

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
    Brando.Villain.Block.merge_ref_template(:template_svg, ref_src, ref_target_changeset, protected_attrs())
  end

  def apply_ref(_src_type, ref_src, ref_target_changeset) do
    Brando.Villain.Block.merge_ref(ref_src, ref_target_changeset, protected_attrs())
  end
end
