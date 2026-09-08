defmodule Brando.Villain.Blocks.MarkdownSourceBlock do
  @moduledoc false
  use Brando.Villain.Block, type: "markdown_source"

  defmodule Data do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "MarkdownSourceBlockData",
      singular: "markdown_source_block_data",
      plural: "markdown_source_block_datas",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded
    identifier false
    persist_identifier false

    attributes do
      attribute :source_id, :integer
      attribute :policy, :enum, values: [:follow, :review, :pinned], default: :review
      attribute :version_id, :integer
    end
  end

  def protected_attrs, do: [:source_id, :policy, :version_id]
end
