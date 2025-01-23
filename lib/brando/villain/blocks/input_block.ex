defmodule Brando.Villain.Blocks.InputBlock do
  @moduledoc false
  use Brando.Villain.Block,
    type: "input"

  defmodule Data do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "InputBlockData",
      singular: "input_block_data",
      plural: "input_block_datas",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded
    identifier false
    persist_identifier false

    attributes do
      attribute :help_text, :text
      attribute :placeholder, :text
      attribute :label, :text
      attribute :type, :text
      attribute :value, :text
    end
  end

  def protected_attrs do
    [:value]
  end
end
