defmodule Brando.MetaRenderTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Brando.HTML
  alias Brando.Factory

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
      plural: "pages",
      gettext_module: Brando.Gettext

    meta_schema do
      field "title", & &1.title
      field "mutated_title", &mutator_function(&1.title)
      field "generated_title", &generator_function/1
      field ["description", "og:description"], &mutator_function(&1.description)
      field "og:url", & &1.__meta__.current_url
    end

    def mutator_function(data), do: "@ #{data}"
    def generator_function(_), do: "Generated."
  end

  test "rendered meta" do
    mock_conn =
      Brando.Plug.HTML.put_meta(
        %Plug.Conn{assigns: %{language: "en"}},
        Brando.MetaRenderTest.Page,
        @mock_data
      )

    assigns = %{mock_conn: mock_conn}

    comp = ~H"""
    <.render_meta conn={@mock_conn} />
    """

    assert rendered_to_string(comp) ==
             "<meta name=\"title\" content=\"Our title\"><meta name=\"mutated_title\" content=\"@ Our title\"><meta name=\"generated_title\" content=\"Generated.\"><meta name=\"description\" content=\"@ Our description\"><meta property=\"og:description\" content=\"@ Our description\"><meta property=\"og:url\" content=\"http://localhost\"><meta property=\"og:title\" content=\"Fallback meta title\"><meta property=\"og:site_name\" content=\"MyApp\"><meta property=\"og:type\" content=\"website\"><meta property=\"og:see_also\" content=\"https://instagram.com/test\"><meta property=\"og:see_also\" content=\"https://facebook.com/test\"><meta name=\"key1\" content=\"value1\"><meta name=\"key2\" content=\"value2\">"

    mock_conn_with_image =
      Brando.Plug.HTML.put_meta(mock_conn, "og:image", "https://test.com/my_image.jpg")

    assigns = %{mock_conn_with_image: mock_conn_with_image}

    comp = ~H"""
    <.render_meta conn={@mock_conn_with_image} />
    """

    assert rendered_to_string(comp) ==
             "<meta name=\"title\" content=\"Our title\"><meta name=\"mutated_title\" content=\"@ Our title\"><meta name=\"generated_title\" content=\"Generated.\"><meta name=\"description\" content=\"@ Our description\"><meta property=\"og:description\" content=\"@ Our description\"><meta property=\"og:url\" content=\"http://localhost\"><meta property=\"og:title\" content=\"Fallback meta title\"><meta property=\"og:site_name\" content=\"MyApp\"><meta property=\"og:type\" content=\"website\"><meta name=\"image\" content=\"https://test.com/my_image.jpg\"><meta property=\"og:image\" content=\"https://test.com/my_image.jpg\"><meta property=\"og:image:type\" content=\"image/jpeg\"><meta property=\"og:see_also\" content=\"https://instagram.com/test\"><meta property=\"og:see_also\" content=\"https://facebook.com/test\"><meta name=\"key1\" content=\"value1\"><meta name=\"key2\" content=\"value2\">"

    # change identity values
    u0 = Factory.insert(:random_user)
    {:ok, meta_img} = Brando.Images.create_image(@img, u0)
    {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})
    Brando.Sites.update_identity(identity, %{links: [], metas: []}, :system)

    {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})
    Brando.Sites.update_seo(seo, %{fallback_meta_image_id: meta_img.id}, :system)

    assigns = %{mock_conn: mock_conn}

    comp = ~H"""
    <.render_meta conn={@mock_conn} />
    """

    assert rendered_to_string(comp) ==
             "<meta name=\"title\" content=\"Our title\"><meta name=\"mutated_title\" content=\"@ Our title\"><meta name=\"generated_title\" content=\"Generated.\"><meta name=\"description\" content=\"@ Our description\"><meta property=\"og:description\" content=\"@ Our description\"><meta property=\"og:url\" content=\"http://localhost\"><meta property=\"og:title\" content=\"Fallback meta title\"><meta property=\"og:site_name\" content=\"MyApp\"><meta property=\"og:type\" content=\"website\"><meta name=\"image\" content=\"http://localhost/media/images/sites/identity/image/xlarge/20ri181teifg.jpg\"><meta property=\"og:image\" content=\"http://localhost/media/images/sites/identity/image/xlarge/20ri181teifg.jpg\"><meta property=\"og:image:type\" content=\"image/jpeg\"><meta property=\"og:image:width\" content=\"1900\"><meta property=\"og:image:height\" content=\"933\">"

    {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})
    Brando.Sites.update_identity(identity, %{links: @links, metas: @metas}, :system)

    {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})
    Brando.Sites.update_seo(seo, %{fallback_meta_image_id: nil}, :system)
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
               brando_skip_title_prefix: false,
               brando_skip_title_postfix: false,
               brando_meta: [
                 {"title", "Our title"},
                 {"mutated_title", "@ Our title"},
                 {"generated_title", "Generated."},
                 {"description", "@ Our description"},
                 {"og:description", "@ Our description"},
                 {"og:url", "http://localhost"},
                 {"description", "My description"},
                 {"og:description", "My description"},
                 {"og:image",
                  "http://localhost/media/images/sites/identity/image/xlarge/20ri181teifg.jpg"},
                 {"title", "My title"}
               ]
             }
           }
  end

  test "ensure we strip out all nil values" do
    mock_conn =
      Brando.Plug.HTML.put_meta(
        %Plug.Conn{assigns: %{language: "en"}},
        Brando.Pages.Page,
        %{title: "My own title", meta_description: nil}
      )

    assigns = %{mock_conn: mock_conn}

    comp = ~H"""
    <.render_meta conn={@mock_conn} />
    """

    assert rendered_to_string(comp) ==
             "<meta name=\"title\" content=\"My own title\"><meta property=\"og:title\" content=\"My own title\"><meta property=\"og:site_name\" content=\"MyApp\"><meta property=\"og:type\" content=\"website\"><meta property=\"og:url\" content=\"http://localhost\"><meta name=\"description\" content=\"Fallback meta description\"><meta property=\"og:description\" content=\"Fallback meta description\"><meta property=\"og:see_also\" content=\"https://instagram.com/test\"><meta property=\"og:see_also\" content=\"https://facebook.com/test\"><meta name=\"key1\" content=\"value1\"><meta name=\"key2\" content=\"value2\">"
  end
end
