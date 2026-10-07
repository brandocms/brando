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

  # The identity and SEO caches outlive each test's sandboxed changes; reload
  # them from the database so a test that changes them cannot leak into others.
  setup do
    Brando.Cache.Identity.set()
    Brando.Cache.SEO.set()
    :ok
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
             "<meta name=\"title\" content=\"Our title\"><meta name=\"mutated_title\" content=\"@ Our title\"><meta name=\"generated_title\" content=\"Generated.\"><meta name=\"description\" content=\"@ Our description\"><meta property=\"og:description\" content=\"@ Our description\"><meta property=\"og:url\" content=\"http://localhost\"><meta property=\"og:title\" content=\"Fallback meta title\"><meta property=\"og:site_name\" content=\"MyApp\"><meta property=\"og:type\" content=\"website\"><meta property=\"og:see_also\" content=\"https://instagram.com/test\"><meta property=\"og:see_also\" content=\"https://facebook.com/test\"><meta name=\"key1\" content=\"value1\"><meta name=\"key2\" content=\"value2\"><meta name=\"twitter:card\" content=\"summary\"><meta name=\"twitter:title\" content=\"Fallback meta title\"><meta name=\"twitter:description\" content=\"@ Our description\">"

    mock_conn_with_image =
      Brando.Plug.HTML.put_meta(mock_conn, "og:image", "https://test.com/my_image.jpg")

    assigns = %{mock_conn_with_image: mock_conn_with_image}

    comp = ~H"""
    <.render_meta conn={@mock_conn_with_image} />
    """

    assert rendered_to_string(comp) ==
             "<meta name=\"title\" content=\"Our title\"><meta name=\"mutated_title\" content=\"@ Our title\"><meta name=\"generated_title\" content=\"Generated.\"><meta name=\"description\" content=\"@ Our description\"><meta property=\"og:description\" content=\"@ Our description\"><meta property=\"og:url\" content=\"http://localhost\"><meta property=\"og:title\" content=\"Fallback meta title\"><meta property=\"og:site_name\" content=\"MyApp\"><meta property=\"og:type\" content=\"website\"><meta name=\"image\" content=\"https://test.com/my_image.jpg\"><meta property=\"og:image\" content=\"https://test.com/my_image.jpg\"><meta property=\"og:image:type\" content=\"image/jpeg\"><meta property=\"og:see_also\" content=\"https://instagram.com/test\"><meta property=\"og:see_also\" content=\"https://facebook.com/test\"><meta name=\"key1\" content=\"value1\"><meta name=\"key2\" content=\"value2\"><meta name=\"twitter:card\" content=\"summary_large_image\"><meta name=\"twitter:title\" content=\"Fallback meta title\"><meta name=\"twitter:description\" content=\"@ Our description\"><meta name=\"twitter:image\" content=\"https://test.com/my_image.jpg\">"

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
             "<meta name=\"title\" content=\"Our title\"><meta name=\"mutated_title\" content=\"@ Our title\"><meta name=\"generated_title\" content=\"Generated.\"><meta name=\"description\" content=\"@ Our description\"><meta property=\"og:description\" content=\"@ Our description\"><meta property=\"og:url\" content=\"http://localhost\"><meta property=\"og:title\" content=\"Fallback meta title\"><meta property=\"og:site_name\" content=\"MyApp\"><meta property=\"og:type\" content=\"website\"><meta name=\"image\" content=\"http://localhost/media/images/sites/identity/image/xlarge/20ri181teifg.jpg\"><meta property=\"og:image\" content=\"http://localhost/media/images/sites/identity/image/xlarge/20ri181teifg.jpg\"><meta property=\"og:image:type\" content=\"image/jpeg\"><meta property=\"og:image:width\" content=\"1900\"><meta property=\"og:image:height\" content=\"933\"><meta name=\"twitter:card\" content=\"summary_large_image\"><meta name=\"twitter:title\" content=\"Fallback meta title\"><meta name=\"twitter:description\" content=\"@ Our description\"><meta name=\"twitter:image\" content=\"http://localhost/media/images/sites/identity/image/xlarge/20ri181teifg.jpg\">"

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
                 {"og:image", "http://localhost/media/images/sites/identity/image/xlarge/20ri181teifg.jpg"},
                 {"title", "My title"}
               ]
             }
           }
  end

  describe "X cards" do
    setup do
      {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})

      # `update_identity/3` also refreshes the identity cache, which outlives
      # the test's database sandbox. Put the seeded identity back, so later
      # tests (the JSON-LD organisation's `sameAs`) don't read these links.
      cached = Brando.Cache.get(:identity)
      on_exit(fn -> Brando.Cache.put(:identity, cached, :infinite) end)

      %{identity: identity}
    end

    test "copy the Open Graph values, with the site's handle from an X profile link", %{identity: identity} do
      links = [%{name: "X", url: "https://x.com/brandocms"} | @links]
      Brando.Sites.update_identity(identity, %{links: links, metas: []}, :system)

      conn =
        %Plug.Conn{assigns: %{language: "en"}}
        |> Brando.Plug.HTML.put_meta(Brando.Pages.Page, %{title: "Moved", meta_description: "Where it went"})
        |> Brando.Plug.HTML.put_meta("og:image", "https://test.com/share.jpg")

      metas = metas(conn)

      assert metas["twitter:card"] == "summary_large_image"
      assert metas["twitter:title"] == "Moved"
      assert metas["twitter:description"] == "Where it went"
      assert metas["twitter:image"] == "https://test.com/share.jpg"
      assert metas["twitter:site"] == "@brandocms"
    end

    test "fall back to a summary card without an image, and keep tags the page set", %{identity: identity} do
      Brando.Sites.update_identity(identity, %{links: [], metas: []}, :system)

      conn =
        %Plug.Conn{assigns: %{language: "en"}}
        |> Brando.Plug.HTML.put_meta(Brando.Pages.Page, %{title: "Plain", meta_description: nil})
        |> Brando.Plug.HTML.put_meta("twitter:title", "Our own X title")

      metas = metas(conn)

      assert metas["twitter:card"] == "summary"
      assert metas["twitter:title"] == "Our own X title"
      refute Map.has_key?(metas, "twitter:image")
      refute Map.has_key?(metas, "twitter:site")
    end
  end

  describe "canonical override" do
    test "an entry's meta_canonical_url replaces its canonical link and og:url" do
      entry = %{title: "Syndicated", meta_description: nil, meta_canonical_url: "https://example.com/original"}

      conn =
        %Plug.Conn{assigns: %{language: "en"}}
        |> Brando.Plug.HTML.put_meta(Brando.Pages.Page, entry)
        |> Plug.Conn.put_private(:brando_hreflangs, [{"en", "http://localhost/en/syndicated"}])

      assert metas(conn)["og:url"] == "https://example.com/original"

      assigns = %{conn: conn}
      html = rendered_to_string(~H"<Brando.HTML.render_hreflangs conn={@conn} />")

      assert html =~ ~s(<link rel="canonical" href="https://example.com/original">)
    end

    test "an empty override keeps the entry's own URL" do
      conn =
        %Plug.Conn{assigns: %{language: "en"}}
        |> Brando.Plug.HTML.put_meta(Brando.Pages.Page, %{title: "Own", meta_canonical_url: nil})
        |> Plug.Conn.put_private(:brando_hreflangs, [{"en", "http://localhost/en/own"}])

      assigns = %{conn: conn}
      html = rendered_to_string(~H"<Brando.HTML.render_hreflangs conn={@conn} />")

      assert html =~ ~s(<link rel="canonical" href="http://localhost/en/own">)
      assert metas(conn)["og:url"] == "http://localhost"
    end

    test "must be an absolute http(s) URL" do
      user = Factory.insert(:random_user)
      page = %Brando.Pages.Page{id: 1, creator_id: user.id}

      for url <- ["/relative", "example.com/page", "ftp://example.com/x", "https://"] do
        changeset = Brando.Pages.Page.changeset(page, %{meta_canonical_url: url}, user)
        assert {_, _} = changeset.errors[:meta_canonical_url], "expected #{url} to be refused"
      end

      changeset = Brando.Pages.Page.changeset(page, %{meta_canonical_url: " https://example.com/a "}, user)
      refute changeset.errors[:meta_canonical_url]
      assert Ecto.Changeset.get_change(changeset, :meta_canonical_url) == "https://example.com/a"
    end
  end

  defp metas(conn) do
    assigns = %{conn: conn}

    ~r/<meta (?:name|property)="([^"]+)" content="([^"]*)"/
    |> Regex.scan(rendered_to_string(~H"<Brando.HTML.render_meta conn={@conn} />"))
    |> Map.new(fn [_, key, value] -> {key, value} end)
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
             "<meta name=\"title\" content=\"My own title\"><meta property=\"og:title\" content=\"My own title\"><meta property=\"og:site_name\" content=\"MyApp\"><meta property=\"og:type\" content=\"website\"><meta property=\"og:url\" content=\"http://localhost\"><meta name=\"description\" content=\"Fallback meta description\"><meta property=\"og:description\" content=\"Fallback meta description\"><meta property=\"og:see_also\" content=\"https://instagram.com/test\"><meta property=\"og:see_also\" content=\"https://facebook.com/test\"><meta name=\"key1\" content=\"value1\"><meta name=\"key2\" content=\"value2\"><meta name=\"twitter:card\" content=\"summary\"><meta name=\"twitter:title\" content=\"My own title\"><meta name=\"twitter:description\" content=\"Fallback meta description\">"
  end
end
