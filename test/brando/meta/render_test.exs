defmodule Brando.MetaRenderTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  import Phoenix.HTML

  @mock_data %{
    title: "Our title",
    description: "Our description"
  }

  @img %{
    alt: nil,
    credits: nil,
    focal: %{"x" => 50, "y" => 50},
    height: 933,
    path: "images/sites/identity/image/20ri181teifg.jpg",
    sizes: %{
      "micro" => "images/sites/identity/image/micro/20ri181teifg.jpg",
      "thumb" => "images/sites/identity/image/thumb/20ri181teifg.jpg",
      "xlarge" => "images/sites/identity/image/xlarge/20ri181teifg.jpg"
    },
    title: nil,
    width: 1900
  }

  @links [
    %{
      name: "Instagram",
      url: "https://instagram.com/test"
    },
    %{
      name: "Facebook",
      url: "https://facebook.com/test"
    }
  ]

  @metas [
    %{
      key: "key1",
      value: "value1"
    },
    %{
      key: "key2",
      value: "value2"
    }
  ]

  defmodule Page do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Pages",
      schema: "Page",
      singular: "page",
      plural: "pages"

    meta_schema do
      meta_field "title", [:title]
      meta_field "mutated_title", [:title], &mutator_function/1
      meta_field "generated_title", &generator_function/1
      meta_field ["description", "og:description"], [:description], &mutator_function/1
      meta_field "og:url", & &1.__meta__.current_url
    end

    def mutator_function(data), do: "@ #{data}"
    def generator_function(_), do: "Generated."
  end

  test "rendered meta" do
    mock_conn = Brando.Plug.HTML.put_meta(%Plug.Conn{}, Brando.MetaRenderTest.Page, @mock_data)
    rendered_meta = Brando.Meta.HTML.render_meta(mock_conn)

    assert safe_to_string(rendered_meta) ==
             "<meta content=\"value2\" name=\"key2\"><meta content=\"value1\" name=\"key1\"><meta content=\"https://facebook.com/test\" property=\"og:see_also\"><meta content=\"https://instagram.com/test\" property=\"og:see_also\"><meta content=\"@ Our description\" name=\"description\"><meta content=\"Generated.\" name=\"generated_title\"><meta content=\"@ Our title\" name=\"mutated_title\"><meta content=\"@ Our description\" property=\"og:description\"><meta content=\"MyApp\" property=\"og:site_name\"><meta content=\"Fallback meta title\" property=\"og:title\"><meta content=\"website\" property=\"og:type\"><meta content=\"http://localhost\" property=\"og:url\"><meta content=\"Our title\" name=\"title\">"

    mock_conn_with_image =
      Brando.Plug.HTML.put_meta(mock_conn, "og:image", "https://test.com/my_image.jpg")

    rendered_meta = Brando.Meta.HTML.render_meta(mock_conn_with_image)

    assert safe_to_string(rendered_meta) ==
             "<meta content=\"value2\" name=\"key2\"><meta content=\"value1\" name=\"key1\"><meta content=\"https://facebook.com/test\" property=\"og:see_also\"><meta content=\"https://instagram.com/test\" property=\"og:see_also\"><meta content=\"@ Our description\" name=\"description\"><meta content=\"Generated.\" name=\"generated_title\"><meta content=\"https://test.com/my_image.jpg\" name=\"image\"><meta content=\"@ Our title\" name=\"mutated_title\"><meta content=\"@ Our description\" property=\"og:description\"><meta content=\"https://test.com/my_image.jpg\" property=\"og:image\"><meta content=\"image/jpeg\" property=\"og:image:type\"><meta content=\"MyApp\" property=\"og:site_name\"><meta content=\"Fallback meta title\" property=\"og:title\"><meta content=\"website\" property=\"og:type\"><meta content=\"http://localhost\" property=\"og:url\"><meta content=\"Our title\" name=\"title\">"

    # change identity values
    {:ok, identity} = Brando.Sites.get_identity()
    Brando.Sites.update_identity(identity, %{links: [], metas: []}, :system)

    {:ok, seo} = Brando.Sites.get_seo()
    Brando.Sites.update_seo(seo, %{fallback_meta_image: @img}, :system)

    rendered_meta = Brando.Meta.HTML.render_meta(mock_conn)

    assert safe_to_string(rendered_meta) ==
             "<meta content=\"@ Our description\" name=\"description\"><meta content=\"Generated.\" name=\"generated_title\"><meta content=\"http://localhost/media/images/sites/identity/image/xlarge/20ri181teifg.jpg\" name=\"image\"><meta content=\"@ Our title\" name=\"mutated_title\"><meta content=\"@ Our description\" property=\"og:description\"><meta content=\"http://localhost/media/images/sites/identity/image/xlarge/20ri181teifg.jpg\" property=\"og:image\"><meta content=\"933\" property=\"og:image:height\"><meta content=\"image/jpeg\" property=\"og:image:type\"><meta content=\"1900\" property=\"og:image:width\"><meta content=\"MyApp\" property=\"og:site_name\"><meta content=\"Fallback meta title\" property=\"og:title\"><meta content=\"website\" property=\"og:type\"><meta content=\"http://localhost\" property=\"og:url\"><meta content=\"Our title\" name=\"title\">"

    {:ok, identity} = Brando.Sites.get_identity()
    Brando.Sites.update_identity(identity, %{links: @links, metas: @metas}, :system)

    {:ok, seo} = Brando.Sites.get_seo()
    Brando.Sites.update_seo(seo, %{fallback_meta_image: nil}, :system)
  end

  test "meta_tag" do
    assert Brando.Meta.HTML.meta_tag(content: "test", another: "yes") |> safe_to_string() ==
             "<meta another=\"yes\" content=\"test\">"

    assert Brando.Meta.HTML.meta_tag("og:image", "content.jpg") |> safe_to_string() ==
             "<meta content=\"content.jpg\" property=\"og:image\">"
  end

  test "put_record_meta" do
    conn = Brando.Plug.HTML.put_meta(%Plug.Conn{}, Brando.MetaRenderTest.Page, @mock_data)

    opts = [
      img_field: :cover,
      img_field_size: "xlarge",
      title_field: :title,
      description_field: :meta_description
    ]

    record = %{
      cover: @img,
      title: "My title",
      meta_description: "My description"
    }

    assert Brando.Meta.HTML.put_record_meta(conn, record, opts) == %Plug.Conn{
             assigns: %{page_title: "My title"},
             private: %{
               brando_meta: %{
                 "description" => "My description",
                 "generated_title" => "Generated.",
                 "mutated_title" => "@ Our title",
                 "og:description" => "My description",
                 "og:image" =>
                   "http://localhost/media/images/sites/identity/image/xlarge/20ri181teifg.jpg",
                 "og:url" => "http://localhost",
                 "title" => "My title"
               }
             }
           }
  end
end
