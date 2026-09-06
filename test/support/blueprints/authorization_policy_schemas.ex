defmodule Brando.AuthorizationTestPolicy do
  @moduledoc false
  import Ecto.Query, only: [where: 3]

  def authorize(_scope, _action, schema) when is_atom(schema), do: :ok
  def authorize(scope, _action, entry), do: entry.creator_id == scope.user_id

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
