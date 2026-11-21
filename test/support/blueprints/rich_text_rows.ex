defmodule Brando.RichTextRows.Entry do
  @moduledoc false
  # Rich text in each kind of subform row (Brando.RichTextRowsTest). Only
  # changesets are built: there are no tables.
  use Brando.Blueprint,
    application: "Brando",
    domain: "RichTextRows",
    schema: "Entry",
    singular: "entry",
    plural: "entries",
    gettext_module: Brando.Gettext

  identifier "{{ entry.title }}"
  # No identifiers rows: a moved identifier's links are looked up in every
  # module that persists them
  persist_identifier false

  attributes do
    attribute :title, :string
    attribute :intro, :text
  end

  relations do
    relation :quotes, :embeds_many, module: Brando.RichTextRows.Quote, on_replace: :delete
    relation :feature, :embeds_one, module: Brando.RichTextRows.Feature, on_replace: :update
    relation :items, :has_many, module: Brando.RichTextRows.Item, on_replace: :delete, cast: true
    relation :checked_items, :has_many, module: Brando.RichTextRows.CheckedItem, on_replace: :delete, cast: true
  end

  forms do
    form do
      tab "Content" do
        fieldset do
          input :title, :text
          input :intro, :rich_text
        end

        fieldset do
          inputs_for :quotes do
            cardinality :many
            style :inline
            default %{}

            input :text, :rich_text
            input :credit, :text
          end

          inputs_for :feature do
            cardinality :one

            input :text, :rich_text
          end

          inputs_for :items do
            cardinality :many
            style :inline
            default %{}

            input :label, :text
            input :text, :rich_text
          end

          inputs_for :checked_items do
            cardinality :many
            style :inline
            default %{}

            input :text, :rich_text
          end
        end
      end
    end
  end
end

defmodule Brando.RichTextRows.Quote do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "RichTextRows",
    schema: "Quote",
    singular: "quote",
    plural: "quotes",
    gettext_module: Brando.Gettext

  data_layer :embedded

  identifier false
  persist_identifier false

  attributes do
    attribute :text, :text
    attribute :credit, :string
  end
end

defmodule Brando.RichTextRows.Feature do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "RichTextRows",
    schema: "Feature",
    singular: "feature",
    plural: "features",
    gettext_module: Brando.Gettext

  data_layer :embedded

  identifier false
  persist_identifier false

  attributes do
    attribute :text, :text
  end
end

defmodule Brando.RichTextRows.Item do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "RichTextRows",
    schema: "Item",
    singular: "item",
    plural: "items",
    gettext_module: Brando.Gettext

  identifier false
  persist_identifier false

  attributes do
    attribute :label, :string
    attribute :text, :text
    # The transformer's save numbers its rows
    attribute :sequence, :integer
  end

  relations do
    relation :entry, :belongs_to, module: Brando.RichTextRows.Entry
  end
end

defmodule Brando.RichTextRows.CheckedItem do
  @moduledoc false
  # A row whose own default form checks its rich text as well
  use Brando.Blueprint,
    application: "Brando",
    domain: "RichTextRows",
    schema: "CheckedItem",
    singular: "checked_item",
    plural: "checked_items",
    gettext_module: Brando.Gettext

  identifier false
  persist_identifier false

  attributes do
    attribute :text, :text
  end

  relations do
    relation :entry, :belongs_to, module: Brando.RichTextRows.Entry
  end

  forms do
    form do
      tab "Content" do
        fieldset do
          input :text, :rich_text
        end
      end
    end
  end
end
