# A synchronized content type whose `subtitle` the forms lock for anyone but a
# superuser (Proposals.TranslateTest: a translate operation refuses a locked
# field as set_fields does), on the `synctest_articles` table.
defmodule Brando.SyncLockedTest.Article do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "SyncLockedTest",
    schema: "Article",
    singular: "article",
    plural: "articles",
    gettext_module: Brando.Gettext

  table "synctest_articles"
  # The articles' table, not their permissions
  authorization(key: "brando.sync_locked_test.article")

  trait :creator
  trait :status
  trait :timestamped
  trait :translatable, mode: :synchronized

  identifier "{{ entry.title }}"

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
    attribute :subtitle, :text
  end

  listings do
    listing do
      query %{order: [{:asc, :id}]}
    end
  end

  forms do
    form do
      tab "Content" do
        fieldset do
          input :title, :text
          input :slug, :slug, source: :title
          input :subtitle, :textarea, readonly: :unless_superuser
        end
      end
    end
  end
end

defmodule Brando.SyncLockedTest do
  @moduledoc false
  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.SyncLockedTest.Article

  query :single, Article, do: fn query -> from(q in query) end

  matches Article do
    fn
      {:id, id}, query -> from t in query, where: t.id == ^id
    end
  end

  query :list, Article, do: fn query -> from(q in query) end

  mutation :create, Article
  mutation :update, Article
  mutation :delete, Article
  mutation :duplicate, {Article, change_fields: [:title, :slug]}
end
