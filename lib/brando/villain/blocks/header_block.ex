defmodule Brando.Villain.Blocks.HeaderBlock do
  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "HeaderBlockData",
      singular: "header_block_data",
      plural: "header_block_datas",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded
    identifier false

    attributes do
      attribute :class, :text
      attribute :text, :text
      attribute :level, :integer
      attribute :link, :text
      attribute :placeholder, :text
      attribute :id, :text
    end
  end

  use Brando.Villain.Block,
    type: "header"

  def protected_attrs do
    [:text]
  end
end
