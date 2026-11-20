defmodule Brando.SyncPolicyTest.Article do
  @moduledoc false
  # A synchronized type whose read policy lets a person read only the entries
  # they created (`Brando.AuthorizationTestPolicy`): someone may read a
  # translation and not its source (TranslationWorkTest). It keeps its rows in
  # `Brando.SyncTest.Article`'s tables.
  use Brando.Blueprint,
    application: "Brando",
    domain: "SyncPolicyTest",
    schema: "Article",
    singular: "article",
    plural: "articles",
    gettext_module: Brando.Gettext

  table "synctest_articles"

  trait :creator
  trait :status
  trait :timestamped
  trait :translatable, mode: :synchronized
  trait :blocks

  authorization(key: "authorization.policy_articles", actions: [:read, :update], policy: Brando.AuthorizationTestPolicy)

  identifier "{{ entry.title }}"

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
  end

  relations do
    relation :blocks, :has_many, module: :blocks
  end

  forms do
    form do
      blocks :blocks

      tab "Content" do
        fieldset do
          input :title, :text
          input :slug, :slug, source: :title
        end
      end
    end
  end
end

defmodule Brando.SyncPolicyTest do
  @moduledoc false
  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.SyncPolicyTest.Article

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
