# A content type a proposal can create, on the `synctest_articles` table, whose
# subtitle carries a `format:` constraint with a `format_message:`
# (Proposals.FormatMessageTest).
defmodule Brando.FormatProposalTest.Note do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "FormatProposalTest",
    schema: "Note",
    singular: "note",
    plural: "notes",
    gettext_module: Brando.Gettext

  table "synctest_articles"
  authorization(key: "brando.format_proposal_test.note")

  trait :status
  trait :timestamped

  identifier "{{ entry.title }}"

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
    attribute :subtitle, :text, constraints: [format: ~r/\.\z/, format_message: "ends with a full stop"]
    attribute :year, :integer, required: true
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
          input :subtitle, :text
          input :year, :number
        end
      end
    end
  end
end

defmodule Brando.FormatProposalTest do
  @moduledoc false
  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.FormatProposalTest.Note

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
