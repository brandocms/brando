defmodule Brando.SyncTest.Article do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "SyncTest",
    schema: "Article",
    singular: "article",
    plural: "articles",
    gettext_module: Brando.Gettext

  @image_cfg [
    allowed_mimetypes: ["image/jpeg", "image/png"],
    default_size: "medium",
    upload_path: Path.join("images", "synced"),
    random_filename: true,
    size_limit: 10_240_000,
    sizes: %{"medium" => %{"size" => "500x500", "quality" => 65, "crop" => true}},
    srcset: [{"medium", "500w"}]
  ]

  trait :creator
  trait :status
  trait :timestamped
  trait :translatable, mode: :synchronized, source_controlled_fields: [:year]
  trait :blocks

  identifier "{{ entry.title }}"

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
    attribute :subtitle, :text
    attribute :year, :integer
    attribute :featured, :boolean, default: false
  end

  assets do
    asset :cover, :image, cfg: @image_cfg
  end

  relations do
    relation :parent, :belongs_to, module: __MODULE__
    # Links to other content, which a copy keeps (TranslationsTest: duplication)
    relation :related_entries, :entries
    relation :blocks, :has_many, module: :blocks
    # Declared only in `form :notes` (FieldActionsLiveTest)
    relation :notes, :has_many, module: :blocks

    relation :items, :has_many,
      module: Brando.SyncTest.ArticleItem,
      on_replace: :delete,
      preload_order: [asc: :sequence],
      cast: true

    # A one-to-one subform with an image field (SubformRelationTest)
    relation :author, :has_one,
      module: Brando.SyncTest.ArticleAuthor,
      on_replace: :update,
      cast: true
  end

  listings do
    listing do
      query %{order: [{:asc, :id}]}
    end

    # What a listing may know about the signed-in user (ListingUserContextTest)
    listing :user_context do
      decorate &Brando.SyncTest.ArticleListing.put_viewer/2
      component &Brando.SyncTest.ArticleListing.row/1
      filter label: "Mine", key: "mine", type: :boolean

      filter do
        label "Kind"
        key("kind")
        type :select
        option("All", nil)
        option("Featured only", "featured_only")
      end

      sort :longest, label: "Longest title", order: &Brando.SyncTest.ArticleListing.longest_title_first/1
      sort :oldest, label: "Oldest", order: [{:asc, :id}]
      selection_action label: "Feature", event: "feature_selected", confirm: "Feature the selected articles?"
      selection_action label: "Never", event: "never_selected", visible: &Brando.SyncTest.ArticleListing.never/1
      selection_action label: "Named", event: "named_selected", visible: &Brando.SyncTest.ArticleListing.named?/1
    end

    # A text, a boolean and a select filter side by side, as an application
    # declares them (ListingFiltersLiveTest)
    listing :filters do
      component &Brando.SyncTest.ArticleListing.title_row/1
      filter label: "Title", key: "title"
      filter label: "Featured only", key: "featured", type: :boolean, default: false

      filter do
        label "Status"
        key("status_filter")
        type :select
        default nil
        option("All", nil)
        option("Published", "published")
        option("Draft", "draft")
      end
    end
  end

  forms do
    form do
      # Hidden only for this title, so the form tests can check `hidden:`
      # on a blocks field without affecting the others.
      blocks :blocks, hidden: {:title, "Hide the blocks"}

      tab "Content" do
        fieldset do
          input :title, :text
          input :slug, :slug, source: :title
          # Two AI actions (FieldActionsLiveTest); they show only where
          # Brando.AI is configured.
          input :subtitle, :textarea,
            ai_actions: [
              summarize: [
                label: "Summarize the article",
                prompt: "Summarize the article for a listing.",
                from: [:title, :blocks],
                max: 160,
                tone: "plain and factual"
              ],
              shorten: [prompt: "Shorten the subtitle.", from: :subtitle]
            ]

          input :year, :number
          input :featured, :toggle
        end

        fieldset do
          inputs_for :items do
            cardinality :many
            style :inline
            default %{}

            input :label, :text
            input :link, :text
            input :cover, :image
            input :clip, :video
          end
        end
      end
    end

    # Both block fields, and an AI action that reads one of them by name
    # (FieldActionsLiveTest)
    form :notes do
      blocks :blocks
      blocks :notes

      tab "Content" do
        fieldset do
          input :title, :text
          input :slug, :slug, source: :title

          input :subtitle, :rich_text,
            write_with_ai: [prompt: "Keep it short.", from: [:notes]],
            ai_actions: [
              outline: [prompt: "Outline the notes.", from: [:notes]],
              everything: [prompt: "Summarize the blocks.", from: [:blocks]],
              shorten: [prompt: "Shorten the subtitle.", from: :subtitle]
            ]
        end
      end
    end

    # Leaves the schema's `blocks` relation out, which a form may do.
    form :no_blocks do
      tab "Content" do
        fieldset do
          input :title, :text
          input :slug, :slug, source: :title

          # Read-only but for superusers: its AI action is not offered to
          # anyone else (FieldActionsLiveTest)
          input :subtitle, :textarea,
            readonly: :unless_superuser,
            ai_actions: [shorten: [prompt: "Shorten the subtitle.", from: :subtitle]]
        end
      end
    end

    # Another tab's save reaching an open form (EntrySavedElsewhereTest): an
    # image of the entry's own beside a has_many subform, and a write after
    # the save.
    form :elsewhere do
      after_save &Brando.SyncTest.Article.write_after_save/2

      tab "Content" do
        fieldset do
          input :title, :text
          input :slug, :slug, source: :title
          input :subtitle, :textarea
          input :cover, :image
        end

        fieldset do
          inputs_for :items do
            cardinality :many
            style :inline
            default %{}

            input :label, :text
            input :link, :text

            input :item_modules, :multi_select,
              options: &Brando.SyncTest.Article.module_options/2,
              relation_key: :module_id,
              relation: :module,
              resetable: true
          end
        end
      end
    end

    # Inputs locked for everyone (ReadonlyFieldsTest): the save takes no
    # value the browser sends for them, but keeps one the form set. A slug
    # is filled in by the browser, so it is never locked.
    form :locked do
      default_params %{"subtitle" => "Set by the form", "language" => "en", "status" => "published"}

      tab "Content" do
        fieldset do
          input :status, :status
          input :title, :text
          input :slug, :slug, source: :title, readonly: true
          input :subtitle, :text, readonly: true
          input :year, :number, disabled: true, default: 2024
          input :featured, :toggle, readonly: true
          input :cover, :image, readonly: true
        end
      end
    end

    # A one-to-one subform with an image field (SubformRelationTest), on the
    # form's automatic preloads.
    form :author do
      tab "Content" do
        fieldset do
          input :title, :text
          input :slug, :slug, source: :title

          inputs_for :author do
            cardinality :one

            input :name, :text
            input :portrait, :image
          end
        end
      end
    end
  end

  # A form's `after_save` that writes to the entry (form `:elsewhere`): a
  # slow one, for a title that asks for it, so another tab's read would find
  # the entry without it if it came first.
  def write_after_save(%{title: "Written after save" <> _} = entry, _user) do
    Process.sleep(300)
    entry |> Ecto.Changeset.change(subtitle: "Set by after_save") |> Brando.Repo.update!()
  end

  def write_after_save(_entry, _user), do: :ok

  def module_options(_, _), do: Brando.Content.list_modules!(%{filter: %{parent_id: nil}, order: "asc name"})
end

defmodule Brando.SyncTest.ArticleItem do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "SyncTest",
    schema: "ArticleItem",
    singular: "article_item",
    plural: "article_items",
    gettext_module: Brando.Gettext

  trait :ensure_uid
  trait :sequenced

  # A row marked for deletion stays in the form (SubformRelationTest)
  @allow_mark_as_deleted true

  identifier false
  persist_identifier false

  attributes do
    attribute :uid, :string
    attribute :label, :string
    attribute :link, :string
  end

  assets do
    asset :cover, :image,
      cfg: [
        allowed_mimetypes: ["image/jpeg", "image/png"],
        default_size: "medium",
        upload_path: Path.join("images", "synced_items"),
        random_filename: true,
        size_limit: 10_240_000,
        sizes: %{"medium" => %{"size" => "500x500", "quality" => 65, "crop" => true}},
        srcset: [{"medium", "500w"}]
      ]

    asset :clip, :video, cfg: :default
  end

  relations do
    relation :article, :belongs_to, module: Brando.SyncTest.Article

    # A multi-select in the row (form `:elsewhere`)
    relation :item_modules, :has_many,
      module: Brando.SyncTest.ArticleItemModule,
      foreign_key: :item_id,
      on_replace: :delete,
      cast: true
  end
end

defmodule Brando.SyncTest.ArticleItemModule do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "SyncTest",
    schema: "ArticleItemModule",
    singular: "article_item_module",
    plural: "article_item_modules",
    gettext_module: Brando.Gettext

  trait :sequenced

  @allow_mark_as_deleted true

  identifier false
  persist_identifier false

  relations do
    relation :item, :belongs_to, module: Brando.SyncTest.ArticleItem
    relation :module, :belongs_to, module: Brando.Content.Module
  end
end

defmodule Brando.SyncTest.ArticleAuthor do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "SyncTest",
    schema: "ArticleAuthor",
    singular: "article_author",
    plural: "article_authors",
    gettext_module: Brando.Gettext

  identifier false
  persist_identifier false

  attributes do
    attribute :name, :string
  end

  assets do
    asset :portrait, :image,
      cfg: [
        allowed_mimetypes: ["image/jpeg", "image/png"],
        default_size: "medium",
        upload_path: Path.join("images", "synced_authors"),
        random_filename: true,
        size_limit: 10_240_000,
        sizes: %{"medium" => %{"size" => "500x500", "quality" => 65, "crop" => true}},
        srcset: [{"medium", "500w"}]
      ]
  end

  relations do
    relation :article, :belongs_to, module: Brando.SyncTest.Article

    # Rows the one-to-one subform owns (TranslationsTest: duplication)
    relation :links, :has_many,
      module: Brando.SyncTest.ArticleAuthorLink,
      foreign_key: :author_id,
      on_replace: :delete,
      cast: true
  end
end

defmodule Brando.SyncTest.ArticleAuthorLink do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "SyncTest",
    schema: "ArticleAuthorLink",
    singular: "article_author_link",
    plural: "article_author_links",
    gettext_module: Brando.Gettext

  trait :blocks

  identifier false
  persist_identifier false

  attributes do
    attribute :label, :string
  end

  assets do
    asset :gallery, :gallery,
      cfg: [
        allowed_mimetypes: ["image/jpeg", "image/png"],
        default_size: "medium",
        upload_path: Path.join("images", "synced_author_links"),
        random_filename: true,
        size_limit: 10_240_000,
        sizes: %{"medium" => %{"size" => "500x500", "quality" => 65, "crop" => true}},
        srcset: [{"medium", "500w"}]
      ]
  end

  relations do
    relation :author, :belongs_to, module: Brando.SyncTest.ArticleAuthor
    relation :blocks, :has_many, module: :blocks
    relation :related_entries, :entries
  end
end
