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
    relation :blocks, :has_many, module: :blocks

    relation :items, :has_many,
      module: Brando.SyncTest.ArticleItem,
      on_replace: :delete,
      preload_order: [asc: :sequence],
      cast: true
  end

  forms do
    form do
      blocks :blocks

      tab "Content" do
        fieldset do
          input :title, :text
          input :slug, :slug, from: :title
          input :subtitle, :textarea
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
