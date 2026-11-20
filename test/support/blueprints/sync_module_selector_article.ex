# A synchronized content type that declares a module selector in
# `source_controlled_fields`, as the i18n guide shows it, on the
# `synctest_articles` table: the selector compiles through the Blueprint DSL
# (Brando.Blueprint.TraitOptionsTest), and the pending-version tests read its
# config (ComputePendingTest).
defmodule Brando.SyncSelectorTest.Article do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "SyncSelectorTest",
    schema: "Article",
    singular: "article",
    plural: "articles",
    gettext_module: Brando.Gettext

  table "synctest_articles"
  # The articles' table, not their permissions
  authorization(key: "brando.sync_selector_test.article")

  trait :creator
  trait :status
  trait :timestamped

  trait :translatable,
    mode: :synchronized,
    source_controlled_fields: [:year, {:module, "hero-banner", [:layout]}]

  identifier "{{ entry.title }}"

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
    attribute :year, :integer
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
          input :year, :number
        end
      end
    end
  end
end
