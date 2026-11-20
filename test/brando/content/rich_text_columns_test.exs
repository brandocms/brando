defmodule Brando.Content.RichTextColumnsTest do
  # The columns a moved identifier's URL is rewritten in: a schema's own
  # rich-text inputs, not a subform's, even one named like a column of the
  # schema that holds no text, which `ilike` cannot read.
  use ExUnit.Case, async: true

  defmodule Quote do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "RichTextColumnsTest",
      schema: "Quote",
      singular: "quote",
      plural: "quotes",
      gettext_module: Brando.Gettext

    data_layer :embedded

    identifier false
    persist_identifier false

    attributes do
      attribute :settings, :text
    end
  end

  defmodule Note do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "RichTextColumnsTest",
      schema: "Note",
      singular: "note",
      plural: "notes",
      gettext_module: Brando.Gettext

    identifier false
    persist_identifier false

    attributes do
      attribute :body, :text
      attribute :settings, :map
    end

    relations do
      relation :quotes, :embeds_many, module: Quote, on_replace: :delete
    end

    forms do
      form do
        tab "Content" do
          fieldset do
            input :body, :rich_text
          end

          fieldset do
            inputs_for :quotes do
              cardinality :many
              style :inline
              default %{}

              input :settings, :rich_text
            end
          end
        end
      end
    end
  end

  test "a schema's own rich-text inputs, not a subform's named like a map column" do
    assert :settings in Note.__rich_text_fields__()
    assert Brando.Content.Blocks.rich_text_fields_for(Note) == [:body]
  end

  test "a schema without rich-text inputs has none" do
    assert Brando.Content.Blocks.rich_text_fields_for(Brando.Content.Var) == []
  end
end
