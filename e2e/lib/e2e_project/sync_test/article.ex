defmodule E2eProject.SyncTest.Article do
  @moduledoc """
  A synchronized translation fixture for the end-to-end suite. It uses the
  `synctest_*` tables of Brando's own synchronized-translation tests.
  """
  use Brando.Blueprint,
    application: "E2eProject",
    domain: "SyncTest",
    schema: "Article",
    singular: "article",
    plural: "articles"

  trait Brando.Trait.Creator
  trait Brando.Trait.Status
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable, mode: :synchronized, source_controlled_fields: [:year, items: [:link]]
  trait Brando.Trait.Blocks

  identifier "{{ entry.title }}"

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
    attribute :subtitle, :text
    attribute :year, :integer
    attribute :featured, :boolean, default: false
  end

  assets do
    asset :cover, :image,
      cfg: [
        allowed_mimetypes: ["image/jpeg", "image/png"],
        default_size: "medium",
        upload_path: Path.join("images", "synced"),
        random_filename: true,
        size_limit: 10_240_000,
        sizes: %{"medium" => %{"size" => "500x500", "quality" => 65, "crop" => true}},
        srcset: [{"medium", "500w"}]
      ]
  end

  relations do
    relation :blocks, :has_many, module: :blocks

    relation :items, :has_many,
      module: E2eProject.SyncTest.ArticleItem,
      on_replace: :delete,
      preload_order: [asc: :sequence],
      cast: true
  end

  listings do
    listing do
      query %{order: [{:asc, :id}]}
    end
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

defmodule E2eProject.SyncTest.ArticleItem do
  @moduledoc false
  use Brando.Blueprint,
    application: "E2eProject",
    domain: "SyncTest",
    schema: "ArticleItem",
    singular: "article_item",
    plural: "article_items"

  trait Brando.Trait.EnsureUID
  trait Brando.Trait.Sequenced

  identifier false
  persist_identifier false

  attributes do
    attribute :uid, :string
    attribute :label, :string
    attribute :link, :string
  end

  relations do
    relation :article, :belongs_to, module: E2eProject.SyncTest.Article
  end
end
