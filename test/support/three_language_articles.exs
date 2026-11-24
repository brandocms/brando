# Articles in three languages, Norwegian, English and German, on a table of
# their own (`three_language_articles`): a version linked to another version,
# such as an independent German article linked to a synchronized group's
# source. A Blueprint's `language` values are the installation's languages
# when it compiles, two in the tests, so test_helper.exs compiles this file
# alone, with German added for its compile. The traits' protocols are
# consolidated by then: these articles have no implementations of them, so
# keep them to the language versions tests.
#
# Their read policy lets a person read only the entries they created
# (`Brando.AuthorizationTestPolicy`), and their update route is the test
# articles' form.
defmodule Brando.ThreeLanguageTest.Article do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "ThreeLanguageTest",
    schema: "Article",
    singular: "article",
    plural: "articles",
    gettext_module: Brando.Gettext

  table "three_language_articles"

  trait :creator
  trait :status
  trait :timestamped
  trait :soft_delete
  trait :translatable, mode: :synchronized

  authorization(
    key: "authorization.three_language_articles",
    actions: [:read, :update],
    policy: Brando.AuthorizationTestPolicy
  )

  identifier "{{ entry.title }}"
  persist_identifier false

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
  end

  listings do
    listing do
      query %{order: [{:asc, :id}]}
    end
  end
end

# The same rows, not synchronized. Its entries are inserted and read with the
# repo: it shares its singular, and so its route, with the synchronized one.
defmodule Brando.ThreeLanguageTest.IndependentArticle do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "ThreeLanguageTest",
    schema: "IndependentArticle",
    singular: "article",
    plural: "articles",
    gettext_module: Brando.Gettext

  table "three_language_articles"

  trait :creator
  trait :status
  trait :timestamped
  trait :soft_delete
  trait :translatable

  authorization(
    key: "authorization.three_language_independent_articles",
    actions: [:read, :update],
    policy: Brando.AuthorizationTestPolicy
  )

  identifier "{{ entry.title }}"
  persist_identifier false

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
  end

  listings do
    listing do
      query %{order: [{:asc, :id}]}
    end
  end
end

defmodule Brando.ThreeLanguageTest do
  @moduledoc false
  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.ThreeLanguageTest.Article

  query :single, Article, do: fn query -> from(q in query) end
  query :list, Article, do: fn query -> from(q in query) end

  matches Article do
    fn {:id, id}, query -> from t in query, where: t.id == ^id end
  end

  mutation :create, Article
  mutation :duplicate, {Article, change_fields: [:title, :slug]}

  @doc """
  Lets `user` read these articles in groups mode, through a group of their
  own: `Brando.Test.Users.grant_permissions/2` takes only the keys of the
  permission catalogue, which lists the Blueprints compiled into the
  application, not these.
  """
  def grant_read(user) do
    alias Brando.Authorization.Grant
    alias Brando.Authorization.Group
    alias Brando.Authorization.Membership
    alias Brando.Repo

    n = System.unique_integer([:positive])
    scope = Brando.Authorization.Scope.current(user)

    group =
      Repo.insert!(%Group{
        key: "three-language-#{n}",
        name: "Three languages #{n}",
        scope_kind: scope.kind,
        site_id: scope.site_id
      })

    Repo.insert!(%Grant{group_id: group.id, permission_key: "authorization.three_language_articles.read"})
    Repo.insert!(%Membership{user_id: user.id, group_id: group.id})
    user
  end
end
