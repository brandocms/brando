defmodule Brando.MetaSchemaTest do
  use ExUnit.Case, async: true

  @mock_data %{
    title: "Our title",
    description: "Our description"
  }

  @data %{
    title: "Our title",
    meta_description: "Our description"
  }

  defmodule Page do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Pages",
      schema: "Page",
      singular: "page",
      plural: "pages"

    meta_schema do
      meta_field "title", [:title]
      meta_field "mutated_title", [:title], fn data -> ">> #{data}" end
      meta_field "generated_title", fn _ -> "Generated." end
      meta_field ["description", "og:description"], [:description], fn data -> "@ #{data}" end
    end

    def mutator_function(data), do: "@ #{data}"
    def generator_function(_), do: "Generated."
  end

  test "extract dummy meta" do
    extracted_meta = Brando.MetaSchemaTest.Page.extract_meta(@mock_data)

    assert extracted_meta["description"] == "@ Our description"
    assert extracted_meta["title"] == "Our title"
    assert extracted_meta["mutated_title"] == ">> Our title"
    assert extracted_meta["generated_title"] == "Generated."
  end

  test "extract real meta" do
    extracted_meta = Brando.Pages.Page.extract_meta(@data)

    assert extracted_meta["description"] == "Our description"
    assert extracted_meta["title"] == "Our title"

    assert :__meta_field__ in Keyword.keys(Brando.Pages.Page.__info__(:functions))
  end

  test "fallback" do
    data = %{meta_title: "META title", title: "Title", foo: "bar"}
    assert Brando.Blueprint.Meta.fallback(data, [:meta_title, :title]) == "META title"
    assert Brando.Blueprint.Meta.fallback(data, [:title, :meta_title]) == "Title"
    assert Brando.Blueprint.Meta.fallback(data, [:title, :foo]) == "Title"
    assert Brando.Blueprint.Meta.fallback(data, [:foo, :title]) == "bar"

    data = %{meta_title: nil, title: "Title", foo: "bar"}
    assert Brando.Blueprint.Meta.fallback(data, [:meta_title, :title]) == "Title"

    data = %{meta_title: nil, title: nil, foo: "bar"}
    assert Brando.Blueprint.Meta.fallback(data, [:meta_title, :title]) == nil
  end
end
