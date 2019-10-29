defmodule Brando.MetaRenderTest do
  use ExUnit.Case, async: true
  import Phoenix.HTML

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
      field "og:url", & &1.__meta__.current_url
    end

    def mutator_function(data), do: "@ #{data}"
    def generator_function(_), do: "Generated."
  end

  test "rendered meta" do
    mock_conn = Brando.Plug.HTML.put_meta(%Plug.Conn{}, Brando.MetaRenderTest.Page, @mock_data)
    rendered_meta = Brando.Meta.HTML.render_meta(mock_conn)

    assert safe_to_string(rendered_meta) ==
             "<meta content=\"@ Our description\" name=\"description\"><meta content=\"Generated.\" name=\"generated_title\"><meta content=\"@ Our title\" name=\"mutated_title\"><meta content=\"@ Our description\" property=\"og:description\"><meta content=\"MyApp\" property=\"og:site_name\"><meta content=\"Firma | Velkommen!\" property=\"og:title\"><meta content=\"website\" property=\"og:type\"><meta content=\"http://localhost\" property=\"og:url\"><meta content=\"Our title\" name=\"title\">"
  end
end
