# Content types a proposal can change whose `language` is not the usual one
# (Proposals.ToolsTest, describe_content_type): plain text in `Plain`, a
# language field with a narrower set of its own in `English`. Both on the
# `synctest_articles` table.
defmodule Brando.LanguageProposalTest.Plain do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "LanguageProposalTest",
    schema: "Plain",
    singular: "plain",
    plural: "plains",
    gettext_module: Brando.Gettext

  table "synctest_articles"
  # The articles' table, not their permissions
  authorization(key: "brando.language_proposal_test.plain")

  trait :timestamped

  identifier "{{ entry.title }}"

  attributes do
    attribute :title, :string
    attribute :language, :string
  end

  listings do
    listing do
      query %{order: [{:asc, :id}]}
    end
  end
end

defmodule Brando.LanguageProposalTest.English do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "LanguageProposalTest",
    schema: "English",
    singular: "english",
    plural: "englishes",
    gettext_module: Brando.Gettext

  table "synctest_articles"
  # The articles' table, not their permissions
  authorization(key: "brando.language_proposal_test.english")

  trait :timestamped

  identifier "{{ entry.title }}"

  attributes do
    attribute :title, :string
    attribute :language, :language, languages: [[value: "en", text: "English"]]
  end

  listings do
    listing do
      query %{order: [{:asc, :id}]}
    end
  end
end

defmodule Brando.LanguageProposalTest do
  @moduledoc false
  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.LanguageProposalTest.{English, Plain}

  query :single, Plain, do: fn query -> from(q in query) end
  query :list, Plain, do: fn query -> from(q in query) end
  query :single, English, do: fn query -> from(q in query) end
  query :list, English, do: fn query -> from(q in query) end

  matches Plain do
    fn
      {:id, id}, query -> from t in query, where: t.id == ^id
    end
  end

  matches English do
    fn
      {:id, id}, query -> from t in query, where: t.id == ^id
    end
  end
end
