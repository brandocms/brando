defmodule Brando.Villain.Blocks.HeaderBlock do
  @moduledoc false
  use Brando.Villain.Block,
    type: "header"

  defmodule Data do
    @moduledoc false
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
    persist_identifier false

    attributes do
      attribute :class, :text
      attribute :text, :text
      attribute :level, :integer
      attribute :link, :text
      attribute :placeholder, :text
      attribute :id, :text
    end
  end

  def protected_attrs do
    [:text]
  end
end
