# Synchronized articles whose slug is unique per language, and ones whose slug
# is unique across the table: the slug a new translation gets (#3869).
defmodule Brando.SlugScopeTest.LanguageArticle do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "SlugScopeTest",
    schema: "LanguageArticle",
    singular: "language_article",
    plural: "language_articles",
    gettext_module: Brando.Gettext

  table "slug_scope_language_articles"

  trait :creator
  trait :status
  trait :timestamped
  trait :translatable, mode: :synchronized

  identifier "{{ entry.title }}"
  persist_identifier false

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true, unique: [prevent_collision: :language]
  end

  listings do
    listing do
      query %{order: [{:asc, :id}]}
    end
  end
end

defmodule Brando.SlugScopeTest.TableArticle do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "SlugScopeTest",
    schema: "TableArticle",
    singular: "table_article",
    plural: "table_articles",
    gettext_module: Brando.Gettext

  table "slug_scope_table_articles"

  trait :creator
  trait :status
  trait :timestamped
  trait :translatable, mode: :synchronized

  identifier "{{ entry.title }}"
  persist_identifier false

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true, unique: [prevent_collision: true]
  end

  listings do
    listing do
      query %{order: [{:asc, :id}]}
    end
  end
end

defmodule Brando.SlugScopeTest do
  @moduledoc false
  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.SlugScopeTest.LanguageArticle
  alias Brando.SlugScopeTest.TableArticle

  query :single, LanguageArticle, do: fn query -> from(q in query) end
  query :single, TableArticle, do: fn query -> from(q in query) end
  query :list, LanguageArticle, do: fn query -> from(q in query) end
  query :list, TableArticle, do: fn query -> from(q in query) end

  matches LanguageArticle do
    fn {:id, id}, query -> from t in query, where: t.id == ^id end
  end

  matches TableArticle do
    fn {:id, id}, query -> from t in query, where: t.id == ^id end
  end

  mutation :create, LanguageArticle
  mutation :create, TableArticle
  mutation :duplicate, {LanguageArticle, change_fields: [:title, :slug]}
  mutation :duplicate, {TableArticle, change_fields: [:title, :slug]}
end
