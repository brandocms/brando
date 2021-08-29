defmodule Brando.Blueprint.Villain.Blocks.SvgBlock do
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

  use Brando.Blueprint.Villain.Block,
    type: "svg"
end
