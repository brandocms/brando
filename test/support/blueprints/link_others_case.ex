defmodule Brando.LinkTest.Case do
  @moduledoc false
  # A case with a page on the site, or only a link to the client's
  # (`absolute_url ..., link_others_to:`; Brando.Blueprint.LinkOthersToTest).
  use Brando.Blueprint,
    application: "Brando",
    domain: "LinkTest",
    schema: "Case",
    singular: "case",
    plural: "cases",
    gettext_module: Brando.Gettext

  identifier "{{ entry.title }}"

  absolute_url ~H"/cases/{@entry.slug}",
    only: %{type: :full_case},
    link_others_to: :external_link

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
    attribute :type, :enum, values: [:full_case, :external_link], default: :full_case
    attribute :external_link, :string
    attribute :summary, :text
  end

  # Rich text in subform rows: in the case's own column, and in a table of
  # their own
  relations do
    relation :highlights, :embeds_many,
      module: Brando.LinkTest.Highlight,
      on_replace: :delete,
      sort_param: :sort_highlight_ids,
      drop_param: :drop_highlight_ids

    relation :lead, :embeds_one, module: Brando.LinkTest.Highlight, on_replace: :update

    # Rows Ecto would not take back as a changeset: one without a primary
    # key, Brando's default `on_replace: :update`; rows whose relation
    # raises on a replace
    relation :note, :embeds_one, module: Brando.LinkTest.Note
    relation :aside, :embeds_one, module: Brando.LinkTest.Highlight, on_replace: :raise

    relation :archive, :embeds_many,
      module: Brando.LinkTest.Highlight,
      on_replace: :raise,
      sort_param: :sort_archive_ids,
      drop_param: :drop_archive_ids

    # Rows an entry's query leaves out
    relation :extras, :embeds_many,
      module: Brando.LinkTest.Highlight,
      on_replace: :delete,
      load_in_query: false,
      sort_param: :sort_extras_ids,
      drop_param: :drop_extras_ids

    relation :chapters, :has_many,
      module: Brando.LinkTest.Chapter,
      cast: true,
      on_replace: :delete,
      sort_param: :sort_chapter_ids,
      drop_param: :drop_chapter_ids
  end

  forms do
    form do
      tab "Content" do
        fieldset do
          input :title, :text
          input :slug, :slug, source: :title

          input :type, :radios,
            options: [%{label: "Full case", value: :full_case}, %{label: "Link", value: :external_link}]

          input :external_link, :text
          # Rich-text links to other cases follow their destination
          input :summary, :rich_text
        end

        fieldset do
          inputs_for :highlights do
            cardinality :many
            style :inline
            default %{}

            input :title, :text
            input :body, :rich_text
          end

          inputs_for :lead do
            input :title, :text
            input :body, :rich_text
          end

          inputs_for :note do
            input :body, :rich_text
          end

          inputs_for :aside do
            input :body, :rich_text
          end

          inputs_for :archive do
            cardinality :many
            style :inline
            default %{}

            input :body, :rich_text
          end

          inputs_for :extras do
            cardinality :many
            style :inline
            default %{}

            input :body, :rich_text
          end

          inputs_for :chapters do
            cardinality :many
            style :inline
            default %{}

            input :title, :text
            input :body, :rich_text
          end
        end
      end
    end
  end
end

defmodule Brando.LinkTest.Highlight do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "LinkTest",
    schema: "Highlight",
    singular: "highlight",
    plural: "highlights",
    gettext_module: Brando.Gettext

  data_layer :embedded
  identifier false
  persist_identifier false

  attributes do
    attribute :title, :string
    attribute :body, :text
  end
end

defmodule Brando.LinkTest.Note do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "LinkTest",
    schema: "Note",
    singular: "note",
    plural: "notes",
    gettext_module: Brando.Gettext

  @primary_key false
  data_layer :embedded
  identifier false
  persist_identifier false

  attributes do
    attribute :label, :string
    attribute :body, :text
  end
end

defmodule Brando.LinkTest.Chapter do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "LinkTest",
    schema: "Chapter",
    singular: "chapter",
    plural: "chapters",
    gettext_module: Brando.Gettext

  identifier false
  persist_identifier false

  attributes do
    attribute :title, :string
    attribute :body, :text
  end

  relations do
    relation :case, :belongs_to, module: Brando.LinkTest.Case
  end

  # A row with a form of its own beside the case's subform: its rich text
  # is found through both, and a row without a case through this one only
  forms do
    form do
      tab "Content" do
        fieldset do
          input :title, :text
          input :body, :rich_text
        end
      end
    end
  end
end

defmodule Brando.LinkTest do
  @moduledoc false
  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.LinkTest.Case

  query :single, Case, do: fn query -> from(q in query) end

  matches Case do
    fn
      {:id, id}, query -> from t in query, where: t.id == ^id
    end
  end

  query :list, Case, do: fn query -> from(q in query) end
end
