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
    relation :blocks, :has_many, module: :blocks

    relation :items, :has_many,
      module: Brando.SyncTest.ArticleItem,
      on_replace: :delete,
      preload_order: [asc: :sequence],
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
          input :slug, :slug, from: :title
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
          end
        end
      end
    end

    # Leaves the schema's `blocks` relation out, which a form may do.
    form :no_blocks do
      tab "Content" do
        fieldset do
          input :title, :text
          input :slug, :slug, from: :title
        end
      end
    end
  end
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

  identifier false
  persist_identifier false

  attributes do
    attribute :uid, :string
    attribute :label, :string
    attribute :link, :string
  end

  relations do
    relation :article, :belongs_to, module: Brando.SyncTest.Article
  end
end
