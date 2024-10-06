defmodule Brando.MetaSchemaTest do
  use ExUnit.Case, async: true

  @mock_data %{
    title: "Our title",
    description: "Our description"
  }

  @data %{
    title: "Our title",
    meta_description: "Our description",
    __meta__: %{
      current_url: "http://localhost",
      language: "en"
    }
  }

  defmodule Page do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Pages",
      schema: "Page",
      singular: "page",
      plural: "pages",
      gettext_module: Brando.Gettext

    meta_schema do
      field "title", & &1.title
      field "mutated_title", fn data -> ">> #{data.title}" end
      field "generated_title", fn _ -> "Generated." end
      field ["description", "og:description"], fn data -> "@ #{data.description}" end
    end

    def mutator_function(data), do: "@ #{data}"
    def generator_function(_), do: "Generated."
  end

  test "extract dummy meta" do
    extracted_meta = Brando.Blueprint.Meta.extract_meta(Brando.MetaSchemaTest.Page, @mock_data)

    assert extracted_meta["description"] == "@ Our description"
    assert extracted_meta["title"] == "Our title"
    assert extracted_meta["mutated_title"] == ">> Our title"
    assert extracted_meta["generated_title"] == "Generated."
  end

  test "extract real meta" do
    extracted_meta = Brando.Blueprint.Meta.extract_meta(Brando.Pages.Page, @data)
    assert extracted_meta["description"] == "Our description"
    assert extracted_meta["title"] == "Our title"
  end

  test "fallback" do
    data = %{meta_title: "META title", title: "Title", foo: "bar"}
    assert Brando.Blueprint.Utils.fallback(data, [:meta_title, :title]) == "META title"
    assert Brando.Blueprint.Utils.fallback(data, [:title, :meta_title]) == "Title"
    assert Brando.Blueprint.Utils.fallback(data, [:title, :foo]) == "Title"
    assert Brando.Blueprint.Utils.fallback(data, [:foo, :title]) == "bar"

    data = %{meta_title: nil, title: "Title", foo: "bar"}
    assert Brando.Blueprint.Utils.fallback(data, [:meta_title, :title]) == "Title"

    data = %{meta_title: nil, title: nil, foo: "bar"}
    assert Brando.Blueprint.Utils.fallback(data, [:meta_title, :title]) == nil

    data = %{title: "<p>Title grabbed from a field with rich text</p>", foo: "bar"}

    assert Brando.Blueprint.Utils.fallback(data, [:meta_title, {:strip_tags, :title}]) ==
             "Title grabbed from a field with rich text"

    data = %{nested: %{nested: "title"}, other: "yes"}
    assert Brando.Blueprint.Utils.fallback(data, [:non_existant, [:nested, :nested]]) == "title"
    assert Brando.Blueprint.Utils.fallback(data, [[:nested, :nested], :non_existant]) == "title"
  end
end
