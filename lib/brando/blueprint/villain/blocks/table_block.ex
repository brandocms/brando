defmodule Brando.Blueprint.Villain.Blocks.TableBlock do
  defmodule Row do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "TableRowBlockData",
      singular: "table_block_row",
      plural: "table_block_rows",
      gettext_module: Brando.Gettext

    alias Brando.Blueprint.Villain.Blocks
    alias Brando.Content.Var

    trait Brando.Trait.CastPolymorphicEmbeds

    @primary_key false
    data_layer :embedded
    identifier ""

    attributes do
      attribute :cols, {:array, PolymorphicEmbed},
        types: [
          boolean: Var.Boolean,
          text: Var.Text,
          string: Var.String,
          datetime: Var.Datetime,
          html: Var.Html,
          color: Var.Color
        ],
        type_field: :type,
        on_type_not_found: :raise,
        on_replace: :delete
    end
  end

  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "TableBlockData",
      singular: "table_block_data",
      plural: "table_block_datas",
      gettext_module: Brando.Gettext

    alias Brando.Blueprint.Villain.Blocks

    @primary_key false
    data_layer :embedded
    identifier "{{ entry.type }}"

    attributes do
      attribute :key, :string, default: "default"
      attribute :instructions, :text
    end

    relations do
      relation :template_row, :embeds_one,
        module: Blocks.TableBlock.Row,
        on_replace: :delete

      relation :rows, :embeds_many,
        module: Blocks.TableBlock.Row,
        on_replace: :delete
    end
  end

  use Brando.Blueprint.Villain.Block,
    type: "table"
end
