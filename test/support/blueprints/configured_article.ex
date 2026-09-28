defmodule Brando.SyncTest.ConfiguredArticle do
  @moduledoc false
  # Its trait options come from an expression, as Page takes them from config.
  use Brando.Blueprint,
    application: "Brando",
    domain: "SyncTest",
    schema: "ConfiguredArticle",
    singular: "configured_article",
    plural: "configured_articles",
    gettext_module: Brando.Gettext

  trait :translatable, Keyword.merge([mode: :synchronized], source_controlled_fields: [:year])

  identifier false
  persist_identifier false

  attributes do
    attribute :title, :string
    attribute :year, :integer
  end
end
