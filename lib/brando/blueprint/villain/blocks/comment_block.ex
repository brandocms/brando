defmodule Brando.Blueprint.Villain.Blocks.CommentBlock do
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
    identifier "{{ entry.type }}"

    attributes do
      attribute :text, :text
    end
  end

  use Brando.Blueprint.Villain.Block,
    type: "comment"
end
