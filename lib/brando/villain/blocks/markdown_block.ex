defmodule Brando.Villain.Blocks.MarkdownBlock do
  @moduledoc false
  use Brando.Villain.Block,
    type: "markdown"

  defmodule Data do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "MarkdownBlockData",
      singular: "markdown_block_data",
      plural: "markdown_block_datas",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded
    identifier false
    persist_identifier false

    attributes do
      attribute :text, :text
    end
  end

  def protected_attrs do
    [:text]
  end
end
