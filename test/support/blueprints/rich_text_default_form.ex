# The default form's rich text, checked by the admin form whatever form an
# editor saves from (RichTextDefaultFormTest), on the `synctest_articles`
# table: the default form draws the subtitle as rich text, `:omitted` leaves
# it out and `:plain` draws it as plain text.
defmodule Brando.RichTextDefaultFormTest.Note do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "RichTextDefaultFormTest",
    schema: "Note",
    singular: "note",
    plural: "notes",
    gettext_module: Brando.Gettext

  table "synctest_articles"
  # The articles' table, not their permissions
  authorization(key: "brando.rich_text_default_form_test.note")

  trait :timestamped
  trait :revisioned

  identifier "{{ entry.title }}"

  attributes do
    attribute :title, :string, required: true
    attribute :subtitle, :text
  end

  forms do
    form do
      tab "Content" do
        fieldset do
          input :title, :text
          input :subtitle, :rich_text
        end
      end
    end

    form :omitted do
      tab "Content" do
        fieldset do
          input :title, :text
        end
      end
    end

    form :plain do
      tab "Content" do
        fieldset do
          input :title, :text
          input :subtitle, :text
        end
      end
    end
  end
end

defmodule Brando.RichTextDefaultFormTest do
  @moduledoc false
  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.RichTextDefaultFormTest.Note

  query :single, Note, do: fn query -> from(q in query) end

  matches Note do
    fn
      {:id, id}, query -> from t in query, where: t.id == ^id
    end
  end

  query :list, Note, do: fn query -> from(q in query) end

  mutation :update, Note
end
