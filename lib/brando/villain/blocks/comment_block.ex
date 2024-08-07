defmodule Brando.Villain.Blocks.CommentBlock do
  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "CommentBlockData",
      singular: "comment_block_data",
      plural: "comment_block_datas",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded
    identifier false
    persist_identifier false

    attributes do
      attribute :text, :text
    end
  end

  use Brando.Villain.Block,
    type: "comment"

  def protected_attrs do
    [:text]
  end
end
