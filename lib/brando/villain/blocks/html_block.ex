defmodule Brando.Villain.Blocks.HtmlBlock do
  @moduledoc false
  use Brando.Villain.Block,
    type: "html"

  defmodule Data do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "HTMLBlockData",
      singular: "html_block_data",
      plural: "html_block_datas",
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
