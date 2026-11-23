defmodule Brando.AuthorizationTestPolicy do
  @moduledoc false
  import Ecto.Query, only: [where: 3]

  def authorize(_scope, _action, schema) when is_atom(schema), do: :ok

  def authorize(scope, _action, entry) do
    # Lets a test make the check fail, as a broken policy or database would
    if error = Process.get(:authorization_test_policy_raises), do: raise(error)
    # Lets a test put an entry with this title out of reach, as a policy on a field can
    denied_title = Process.get(:authorization_test_policy_denies_title)
    entry.creator_id == scope.user_id and (is_nil(denied_title) or Map.get(entry, :title) != denied_title)
  end

  def scope(scope, :export, query),
    do: where(query, [entry], entry.creator_id == ^scope.user_id and entry.title == "Exportable")

  def scope(scope, _action, query), do: where(query, [entry], entry.creator_id == ^scope.user_id)
end

defmodule Brando.AuthorizationTestPolicyWithoutScope do
  @moduledoc false
  def authorize(_, _, _), do: :ok
end

defmodule Brando.AuthorizationTestResources.Page do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "AuthorizationTestResources",
    schema: "Page",
    singular: "page",
    plural: "pages",
    gettext_module: Brando.Gettext

  table "pages"

  authorization(
    key: "authorization.policy_pages",
    actions: [:read, :update, :export],
    policy: Brando.AuthorizationTestPolicy
  )

  attributes do
    attribute :title, :string
    attribute :creator_id, :integer
  end
end

defmodule Brando.AuthorizationTestResources.UnscopedPage do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "AuthorizationTestResources",
    schema: "UnscopedPage",
    singular: "unscoped_page",
    plural: "unscoped_pages",
    gettext_module: Brando.Gettext

  table "pages"
  authorization(key: "authorization.unscoped_pages", actions: [:read], policy: Brando.AuthorizationTestPolicyWithoutScope)

  attributes do
    attribute :title, :string
  end
end

defmodule Brando.AuthorizationTestResources.Snippet do
  @moduledoc false
  # Language versions matched by key, behind a record policy: each editor
  # reads only the snippets they made (`Brando.AuthorizationTestPolicy`)
  use Brando.Blueprint,
    application: "Brando",
    domain: "AuthorizationTestResources",
    schema: "Snippet",
    singular: "snippet",
    plural: "snippets",
    gettext_module: Brando.Gettext

  table "authorization_test_snippets"

  authorization(key: "authorization.policy_snippets", actions: [:read, :update], policy: Brando.AuthorizationTestPolicy)

  trait :timestamped
  trait :translatable, matched_by: [:key]

  identifier "{{ entry.title }}"
  persist_identifier false

  attributes do
    attribute :title, :string
    attribute :key, :string
    attribute :creator_id, :integer
  end
end
