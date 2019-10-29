defmodule Brando.MetaSchemaTest do
  use ExUnit.Case, async: true

  @mock_data %{
    title: "Our title",
    description: "Our description"
  }

  defmodule Page do
    use Brando.Meta.Schema

    meta_schema do
      field "title", [:title]
      field "mutated_title", [:title], &mutator_function/1
      field "generated_title", &generator_function/1
      field ["description", "og:description"], [:description], &mutator_function/1
    end

    def mutator_function(data), do: "@ #{data}"
    def generator_function(_), do: "Generated."
  end

  test "extract meta" do
    extracted_meta = Brando.MetaSchemaTest.Page.extract_meta(@mock_data)

    assert extracted_meta["description"] == "@ Our description"
    assert extracted_meta["title"] == "Our title"
    assert extracted_meta["mutated_title"] == "@ Our title"
    assert extracted_meta["generated_title"] == "Generated."
  end
end
