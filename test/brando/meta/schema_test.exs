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
    use Brando.Meta.Schema

    meta_schema do
      field "title", [:title]
      field "mutated_title", [:title], fn data -> ">> #{data}" end
      field "generated_title", fn _ -> "Generated." end
      field ["description", "og:description"], [:description], fn data -> "@ #{data}" end
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
end
