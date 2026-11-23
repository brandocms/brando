# Synchronized articles with a required category, on their own table
# (`synctest_categorized_articles`): an application's relations to schemas with
# language links, which a translation does not map onto the related entry's
# version in its language (TreeRelationsTest). Categories have language links.
defmodule Brando.SyncCategoryTest.Category do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "SyncCategoryTest",
    schema: "Category",
    singular: "category",
    plural: "categories",
    gettext_module: Brando.Gettext

  table "synctest_categories"

  trait :timestamped
  trait :translatable

  identifier "{{ entry.title }}"
  persist_identifier false

  attributes do
    attribute :title, :string
  end
end

# The category is each language's own
defmodule Brando.SyncCategoryTest.Article do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "SyncCategoryTest",
    schema: "Article",
    singular: "article",
    plural: "articles",
    gettext_module: Brando.Gettext

  table "synctest_categorized_articles"
  authorization(key: "brando.sync_category_test.article")

  trait :creator
  trait :status
  trait :timestamped
  trait :translatable, mode: :synchronized

  identifier "{{ entry.title }}"
  persist_identifier false

  attributes do
    attribute :title, :string, required: true
  end

  relations do
    relation :category, :belongs_to, module: Brando.SyncCategoryTest.Category, required: true
    relation :page, :belongs_to, module: Brando.Pages.Page
  end

  # A text input: the title is translated, so a translation has work
  forms do
    form do
      tab "Content" do
        fieldset do
          input :title, :text
        end
      end
    end
  end
end

# The category and the page follow the source
defmodule Brando.SyncCategoryTest.ControlledArticle do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "SyncCategoryTest",
    schema: "ControlledArticle",
    singular: "controlled_article",
    plural: "controlled_articles",
    gettext_module: Brando.Gettext

  table "synctest_categorized_articles"
  authorization(key: "brando.sync_category_test.controlled_article")

  trait :creator
  trait :status
  trait :timestamped
  trait :translatable, mode: :synchronized, source_controlled_fields: [:category, :page]

  identifier "{{ entry.title }}"
  persist_identifier false

  attributes do
    attribute :title, :string, required: true
  end

  relations do
    relation :category, :belongs_to, module: Brando.SyncCategoryTest.Category, required: true
    relation :page, :belongs_to, module: Brando.Pages.Page
  end

  # A text input: the title is translated, so a translation has work
  forms do
    form do
      tab "Content" do
        fieldset do
          input :title, :text
        end
      end
    end
  end
end

defmodule Brando.SyncCategoryTest do
  @moduledoc false
  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.SyncCategoryTest.Article
  alias Brando.SyncCategoryTest.ControlledArticle

  query :single, Article, do: fn query -> from(q in query) end
  query :single, ControlledArticle, do: fn query -> from(q in query) end

  matches Article do
    fn {:id, id}, query -> from t in query, where: t.id == ^id end
  end

  matches ControlledArticle do
    fn {:id, id}, query -> from t in query, where: t.id == ^id end
  end

  mutation :duplicate, {Article, change_fields: [:title]}
  mutation :duplicate, {ControlledArticle, change_fields: [:title]}
end
