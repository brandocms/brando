defmodule Brando.Villain.Blocks.SvgBlock do
  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "SvgBlockData",
      singular: "svg_block_data",
      plural: "svg_block_datas",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded
    identifier "{{ entry.type }}"

    attributes do
      attribute :class, :text
      attribute :code, :text
    end
  end

  use Brando.Villain.Block,
    type: "svg"

  def protected_attrs do
    [:code]
  end

  def apply_ref(Brando.Villain.Blocks.MediaBlock, ref_src, ref_target) do
    # in order to not overwrite the chosen media block, we have to get the media
    # block template and merge against this instead
    tpl_src = ref_src.data.data.template_svg
    protected_attrs = __MODULE__.protected_attrs()
    overwritten_attrs = Map.keys(tpl_src) -- protected_attrs
    new_attrs = Map.take(tpl_src, overwritten_attrs)
    new_data = Map.merge(ref_target.data.data, new_attrs)
    put_in(ref_target, [Access.key(:data), Access.key(:data)], new_data)
  end

  def apply_ref(_, ref_src, ref_target) do
    protected_attrs = __MODULE__.protected_attrs()
    overwritten_attrs = Map.keys(ref_src.data.data) -- protected_attrs
    new_attrs = Map.take(ref_src.data.data, overwritten_attrs)
    new_data = Map.merge(ref_target.data.data, new_attrs)
    put_in(ref_target, [Access.key(:data), Access.key(:data)], new_data)
  end
end
