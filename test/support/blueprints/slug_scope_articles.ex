# Synchronized articles whose slug is unique per language, per language and
# status, or across the table: the slug a new translation gets (#3869). The
# Independent ones share the tables in independent mode, whose listing rows
# offer Translate to [language].
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

defmodule Brando.SlugScopeTest.StatusArticle do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "SlugScopeTest",
    schema: "StatusArticle",
    singular: "status_article",
    plural: "status_articles",
    gettext_module: Brando.Gettext

  table "slug_scope_status_articles"

  trait :creator
  trait :status
  trait :timestamped
  trait :translatable, mode: :synchronized

  identifier "{{ entry.title }}"
  persist_identifier false

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true, unique: [prevent_collision: [:language, :status]]
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

defmodule Brando.SlugScopeTest.IndependentLanguageArticle do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "SlugScopeTest",
    schema: "IndependentLanguageArticle",
    singular: "independent_language_article",
    plural: "independent_language_articles",
    gettext_module: Brando.Gettext

  table "slug_scope_language_articles"

  trait :creator
  trait :status
  trait :timestamped
  trait :translatable

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

defmodule Brando.SlugScopeTest.IndependentTableArticle do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "SlugScopeTest",
    schema: "IndependentTableArticle",
    singular: "independent_table_article",
    plural: "independent_table_articles",
    gettext_module: Brando.Gettext

  table "slug_scope_table_articles"

  trait :creator
  trait :status
  trait :timestamped
  trait :translatable

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

  alias Brando.SlugScopeTest.IndependentLanguageArticle
  alias Brando.SlugScopeTest.IndependentTableArticle
  alias Brando.SlugScopeTest.LanguageArticle
  alias Brando.SlugScopeTest.StatusArticle
  alias Brando.SlugScopeTest.TableArticle

  query :single, IndependentLanguageArticle, do: fn query -> from(q in query) end
  query :single, IndependentTableArticle, do: fn query -> from(q in query) end
  query :single, LanguageArticle, do: fn query -> from(q in query) end
  query :single, StatusArticle, do: fn query -> from(q in query) end
  query :single, TableArticle, do: fn query -> from(q in query) end
  query :list, IndependentLanguageArticle, do: fn query -> from(q in query) end
  query :list, IndependentTableArticle, do: fn query -> from(q in query) end
  query :list, LanguageArticle, do: fn query -> from(q in query) end
  query :list, StatusArticle, do: fn query -> from(q in query) end
  query :list, TableArticle, do: fn query -> from(q in query) end

  matches IndependentLanguageArticle do
    fn {:id, id}, query -> from t in query, where: t.id == ^id end
  end

  matches IndependentTableArticle do
    fn {:id, id}, query -> from t in query, where: t.id == ^id end
  end

  matches LanguageArticle do
    fn {:id, id}, query -> from t in query, where: t.id == ^id end
  end

  matches StatusArticle do
    fn {:id, id}, query -> from t in query, where: t.id == ^id end
  end

  matches TableArticle do
    fn {:id, id}, query -> from t in query, where: t.id == ^id end
  end

  mutation :create, IndependentLanguageArticle
  mutation :create, IndependentTableArticle
  mutation :create, LanguageArticle
  mutation :create, StatusArticle
  mutation :create, TableArticle
  mutation :duplicate, {IndependentLanguageArticle, change_fields: [:title, :slug]}
  mutation :duplicate, {IndependentTableArticle, change_fields: [:title, :slug]}
  mutation :duplicate, {LanguageArticle, change_fields: [:title, :slug]}
  mutation :duplicate, {StatusArticle, change_fields: [:title, :slug]}
  mutation :duplicate, {TableArticle, change_fields: [:title, :slug]}
end
