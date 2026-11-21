defmodule Brando.RichTextRows.Entry do
  @moduledoc false
  # Rich text in each kind of subform row (Brando.RichTextRowsTest). Only
  # changesets are built; the tables are there because a moved identifier's
  # links are looked for in every Blueprint with a table.
  use Brando.Blueprint,
    application: "Brando",
    domain: "RichTextRows",
    schema: "Entry",
    singular: "entry",
    plural: "entries",
    gettext_module: Brando.Gettext

  identifier "{{ entry.title }}"
  # No identifiers rows of its own
  persist_identifier false

  attributes do
    attribute :title, :string
    attribute :intro, :text
  end

  relations do
    relation :quotes, :embeds_many,
      module: Brando.RichTextRows.Quote,
      on_replace: :delete,
      sort_param: :sort_quotes_ids,
      drop_param: :drop_quotes_ids

    relation :feature, :embeds_one, module: Brando.RichTextRows.Feature, on_replace: :update

    relation :items, :has_many,
      module: Brando.RichTextRows.Item,
      on_replace: :delete,
      cast: true,
      sort_param: :sort_items_ids,
      drop_param: :drop_items_ids

    relation :checked_items, :has_many,
      module: Brando.RichTextRows.CheckedItem,
      on_replace: :delete,
      cast: true,
      sort_param: :sort_checked_items_ids,
      drop_param: :drop_checked_items_ids
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

defmodule Brando.RichTextRows.Plain do
  @moduledoc false
  # A plain `text` column beside rows whose rich-text input is also named
  # `text` (Brando.RichTextParentColumnsTest). Only changesets and structs
  # are built; the table is there for the same reason as the entries'.
  use Brando.Blueprint,
    application: "Brando",
    domain: "RichTextRows",
    schema: "Plain",
    singular: "plain",
    plural: "plains",
    gettext_module: Brando.Gettext

  identifier "{{ entry.title }}"
  persist_identifier false

  attributes do
    attribute :title, :string
    attribute :text, :text
  end

  relations do
    relation :quotes, :embeds_many,
      module: Brando.RichTextRows.Quote,
      on_replace: :delete,
      sort_param: :sort_quotes_ids,
      drop_param: :drop_quotes_ids
  end

  forms do
    form do
      tab "Content" do
        fieldset do
          input :title, :text
          input :text, :textarea
        end

        fieldset do
          inputs_for :quotes do
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

defmodule Brando.RichTextRows.Disagreeing do
  @moduledoc false
  # Forms that disagree on a field, at the top and in each kind of row, and
  # fields only named forms draw (Brando.Villain.RichTextTemplateReadsTest,
  # Brando.Villain.RichTextRowsPrintingTest). Only structs are built; the
  # tables are there because a moved identifier's links are looked for in
  # every Blueprint with rich text.
  use Brando.Blueprint,
    application: "Brando",
    domain: "RichTextRows",
    schema: "Disagreeing",
    singular: "disagreeing",
    plural: "disagreeings",
    gettext_module: Brando.Gettext

  identifier "{{ entry.title }}"
  persist_identifier false

  attributes do
    attribute :title, :string
    attribute :intro, :text
    attribute :aside, :text
  end

  relations do
    relation :quotes, :embeds_many,
      module: Brando.RichTextRows.Quote,
      on_replace: :delete,
      sort_param: :sort_quotes_ids,
      drop_param: :drop_quotes_ids

    relation :feature, :embeds_one, module: Brando.RichTextRows.Feature, on_replace: :update

    relation :notes, :embeds_many,
      module: Brando.RichTextRows.Quote,
      on_replace: :delete,
      sort_param: :sort_notes_ids,
      drop_param: :drop_notes_ids

    relation :items, :has_many,
      module: Brando.RichTextRows.DisagreeingItem,
      on_replace: :delete,
      preload_order: [asc: :sequence],
      cast: true,
      sort_param: :sort_items_ids,
      drop_param: :drop_items_ids

    relation :lead, :has_one, module: Brando.RichTextRows.DisagreeingItem, on_replace: :update, cast: true
  end

  forms do
    # `intro` is rich text here and plain text in `form :plain`. So are a
    # feature's text, and the row fields drawn here as plain text are rich
    # text in `form :plain`.
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

            input :text, :textarea
            input :credit, :text
          end

          inputs_for :feature do
            cardinality :one

            input :text, :rich_text
          end

          inputs_for :items do
            cardinality :many
            style {:transformer, :cover}
            add_entry false

            input :text, :textarea
          end

          inputs_for :lead do
            cardinality :one

            input :text, :textarea
          end
        end
      end
    end

    # `aside` and a note's text are drawn only by named forms, each as rich
    # text; a note's credit by named forms that disagree
    form :plain do
      tab "Content" do
        fieldset do
          input :title, :text
          input :intro, :textarea
          input :aside, :rich_text
        end

        fieldset do
          inputs_for :quotes do
            cardinality :many
            style :inline
            default %{}

            input :text, :rich_text
          end

          inputs_for :feature do
            cardinality :one

            input :text, :textarea
          end

          inputs_for :notes do
            cardinality :many
            style :inline
            default %{}

            input :text, :rich_text
            input :credit, :text
          end

          inputs_for :items do
            cardinality :many
            style :inline
            default %{}

            input :text, :rich_text
          end

          inputs_for :lead do
            cardinality :one

            input :text, :rich_text
          end
        end
      end
    end

    form :aside do
      tab "Content" do
        fieldset do
          input :aside, :rich_text
        end

        fieldset do
          inputs_for :notes do
            cardinality :many
            style :inline
            default %{}

            input :text, :rich_text
            input :credit, :rich_text
          end
        end
      end
    end
  end
end

defmodule Brando.RichTextRows.DisagreeingItem do
  @moduledoc false
  # Disagreeing's `has_many` rows, drawn by a transformer in its default
  # form, and its `has_one` row
  use Brando.Blueprint,
    application: "Brando",
    domain: "RichTextRows",
    schema: "DisagreeingItem",
    singular: "disagreeing_item",
    plural: "disagreeing_items",
    gettext_module: Brando.Gettext

  identifier false
  persist_identifier false

  attributes do
    attribute :text, :text
    # The transformer's save numbers its rows
    attribute :sequence, :integer
  end

  assets do
    asset :cover, :image,
      cfg: [
        allowed_mimetypes: ["image/jpeg", "image/png"],
        default_size: "medium",
        upload_path: Path.join("images", "richtextrows_items"),
        random_filename: true,
        size_limit: 10_240_000,
        sizes: %{"medium" => %{"size" => "500x500", "quality" => 65, "crop" => true}},
        srcset: [{"medium", "500w"}]
      ]
  end

  relations do
    relation :disagreeing, :belongs_to, module: Brando.RichTextRows.Disagreeing
  end
end
