defmodule Brando.ScheduledPolicyTest.Policy do
  @moduledoc false
  # A record policy like the one in the authorization guide: a page titled
  # "Off limits" is neither readable nor writable in the admin.
  import Ecto.Query, only: [where: 3]

  def authorize(_scope, _action, schema) when is_atom(schema), do: :ok
  def authorize(_scope, _action, entry), do: entry.title != "Off limits"

  def scope(_scope, _action, query), do: where(query, [entry], entry.title != "Off limits")
end

defmodule Brando.ScheduledPolicyTest.Page do
  @moduledoc false
  # Pages with a record policy, for scheduled publishing refused by policy
  # (`Brando.PublisherRefusedTest`). The dates are plain attributes rather
  # than `trait :scheduled_publishing`, so the sweep leaves this view of the
  # pages table to `Brando.Pages.Page`.
  use Brando.Blueprint,
    application: "Brando",
    domain: "ScheduledPolicyTest",
    schema: "Page",
    singular: "page",
    plural: "pages",
    gettext_module: Brando.Gettext

  table "pages"

  trait :status

  authorization(
    key: "authorization.scheduled_policy_pages",
    actions: [:schedule],
    policy: Brando.ScheduledPolicyTest.Policy
  )

  attributes do
    attribute :title, :string
    attribute :creator_id, :integer
    attribute :publish_at, :datetime
    attribute :unpublish_at, :datetime
  end
end

defmodule Brando.ScheduledPolicyTest do
  @moduledoc false
  use Brando.Query

  import Ecto.Query

  alias Brando.ScheduledPolicyTest.Page

  query :single, Page, do: fn query -> from(q in query) end

  matches Page do
    fn
      {:id, id}, query -> from t in query, where: t.id == ^id
    end
  end

  mutation :update, Page
end
