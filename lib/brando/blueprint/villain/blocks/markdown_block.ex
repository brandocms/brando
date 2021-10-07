defmodule Brando.Blueprint.Villain.Blocks.MarkdownBlock do
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

  use Brando.Blueprint.Villain.Block,
    type: "markdown"
end
