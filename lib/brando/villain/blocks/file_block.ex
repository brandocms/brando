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

  def apply_ref(Brando.Villain.Blocks.MediaBlock, ref_src, ref_target_changeset) do
    Brando.Villain.Block.merge_ref_template(:template_file, ref_src, ref_target_changeset, protected_attrs())
  end

  def apply_ref(_src_type, ref_src, ref_target_changeset) do
    Brando.Villain.Block.merge_ref(ref_src, ref_target_changeset, protected_attrs())
  end
end
