defmodule Brando.Villain.Blocks.InputBlock do
  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "InputBlockData",
      singular: "input_block_data",
      plural: "input_block_datas",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded
    identifier "{{ entry.type }}"

    attributes do
      attribute :help_text, :text
      attribute :placeholder, :text
      attribute :label, :text
      attribute :type, :text
      attribute :value, :text
    end
  end

  use Brando.Villain.Block,
    type: "input"

  def protected_attrs do
    [:text]
  end
end
