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
