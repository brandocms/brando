defmodule Brando.Villain.Blocks.MarkdownBlock do
  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "MarkdownBlockData",
      singular: "markdown_block_data",
      plural: "markdown_block_datas",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded
    identifier "{{ entry.type }}"

    attributes do
      attribute :text, :text
    end
  end

  use Brando.Villain.Block,
    type: "markdown"

  def protected_attrs do
    [:text]
  end
end
