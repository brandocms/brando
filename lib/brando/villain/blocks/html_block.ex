defmodule Brando.Villain.Blocks.HtmlBlock do
  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "HTMLBlockData",
      singular: "html_block_data",
      plural: "html_block_datas",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded
    identifier "{{ entry.type }}"

    attributes do
      attribute :text, :text
    end
  end

  use Brando.Villain.Block,
    type: "html"

  def protected_attrs do
    [:text]
  end
end
