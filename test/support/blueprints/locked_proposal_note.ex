# A content type a proposal can change whose `subtitle` and `status` are locked
# for anyone but a superuser in every form (Proposals.LockedFieldsTest), on the
# `synctest_articles` table.
defmodule Brando.LockedProposalTest.Note do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "LockedProposalTest",
    schema: "Note",
    singular: "note",
    plural: "notes",
    gettext_module: Brando.Gettext

  table "synctest_articles"
  # The articles' table, not their permissions
  authorization(key: "brando.locked_proposal_test.note")

  trait :status
  trait :timestamped

  identifier "{{ entry.title }}"

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :string
    attribute :subtitle, :text
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
          input :status, :status, readonly: :unless_superuser
          input :title, :text
          input :subtitle, :text, readonly: :unless_superuser
        end
      end
    end
  end
end

defmodule Brando.LockedProposalTest do
  @moduledoc false
  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.LockedProposalTest.Note

  query :single, Note, do: fn query -> from(q in query) end

  matches Note do
    fn
      {:id, id}, query -> from t in query, where: t.id == ^id
    end
  end

  query :list, Note, do: fn query -> from(q in query) end

  mutation :create, Note
  mutation :update, Note
end
