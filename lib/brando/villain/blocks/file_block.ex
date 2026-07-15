defmodule Brando.Villain.Blocks.FileBlock do
  @moduledoc false
  use Brando.Villain.Block, type: "file"

  defmodule Data do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "FileBlockData",
      singular: "file_block_data",
      plural: "file_block_datas",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded
    identifier false
    persist_identifier false

    attributes do
      # Per-usage overrides. Nil means "use the canonical file value".
      attribute :title, :text
      attribute :label, :text
      attribute :description, :text

      attribute :class, :text
      attribute :target_blank, :boolean, default: false
      attribute :download, :boolean, default: true
      attribute :config_target, :text
    end
  end
end
