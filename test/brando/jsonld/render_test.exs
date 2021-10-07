defmodule Brando.JSONLDRenderTest do
  use ExUnit.Case
  use Brando.ConnCase, async: false

  @mock_data %{
    __meta__: %{
      current_url: "http://localhost"
    },
    inserted_at: ~N[2000-01-01 23:00:00],
    updated_at: ~N[2000-01-01 23:30:00],
    language: "no",
    title: "Title of page",
    meta_description: "Meta description"
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

  test "render json ld" do
    {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})
    Brando.Sites.update_identity(identity.id, %{links: @links}, :system)

    {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})
    Brando.Sites.update_seo(seo, %{fallback_meta_image: @img}, :system)

    mock_conn =
      %Plug.Conn{}
      |> Brando.Plug.I18n.put_locale(skip_session: true)
      |> Brando.Plug.HTML.put_json_ld(Brando.Pages.Page, @mock_data)

    rendered_json_ld = Brando.HTML.render_json_ld(mock_conn)

    assert rendered_json_ld == [
             [],
             {:safe,
              [
                60,
                "script",
                [32, "type", 61, 34, "application/ld+json", 34],
                62,
                "{\"@context\":\"http://schema.org\",\"@id\":\"http://localhost/#identity\",\"@type\":\"Organization\",\"address\":{\"@type\":\"PostalAddress\",\"addressCountry\":\"NO\",\"addressLocality\":\"Oslo\",\"addressRegion\":\"Oslo\",\"postalCode\":\"0000\"},\"alternateName\":\"Shortform name\",\"description\":\"Fallback meta description\",\"email\":\"mail@domain.tld\",\"image\":{\"@type\":\"ImageObject\",\"height\":933,\"url\":\"http://localhost/media/images/sites/identity/image/xlarge/20ri181teifg.jpg\",\"width\":1900},\"name\":\"Organization name\",\"sameAs\":[\"https://instagram.com/test\",\"https://facebook.com/test\"],\"url\":\"https://www.domain.tld\"}",
                60,
                47,
                "script",
                62
              ]},
             {:safe,
              [
                60,
                "script",
                [32, "type", 61, 34, "application/ld+json", 34],
                62,
                "{\"@context\":\"http://schema.org\",\"@type\":\"Article\",\"author\":{\"@id\":\"http://localhost/#identity\"},\"copyrightHolder\":{\"@id\":\"http://localhost/#identity\"},\"copyrightYear\":2000,\"creator\":{\"@id\":\"http://localhost/#identity\"},\"dateModified\":\"2000-01-01T23:30:00Z\",\"datePublished\":\"2000-01-01T23:00:00Z\",\"description\":\"Meta description\",\"headline\":\"Title of page\",\"inLanguage\":\"no\",\"mainEntityOfPage\":\"http://localhost\",\"name\":\"Title of page\",\"publisher\":{\"@id\":\"http://localhost/#identity\"},\"url\":\"http://localhost\"}",
                60,
                47,
                "script",
                62
              ]}
           ]

    {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})
    Brando.Sites.update_seo(seo, %{fallback_meta_image: nil}, :system)
  end

  test "render json ld :corporation" do
    {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})
    {:ok, identity} = Brando.Sites.update_identity(identity.id, %{links: @links}, :system)

    {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})
    {:ok, updated_seo} = Brando.Sites.update_seo(seo, %{fallback_meta_image: @img}, :system)

    rendered_json_ld = Brando.HTML.render_json_ld(:corporation, {identity, updated_seo})

    assert rendered_json_ld ==
             {:safe,
              [
                60,
                "script",
                [32, "type", 61, 34, "application/ld+json", 34],
                62,
                "{\"@context\":\"http://schema.org\",\"@id\":\"http://localhost/#identity\",\"@type\":\"Corporation\",\"address\":{\"@type\":\"PostalAddress\",\"addressCountry\":\"NO\",\"addressLocality\":\"Oslo\",\"addressRegion\":\"Oslo\",\"postalCode\":\"0000\"},\"alternateName\":\"Shortform name\",\"description\":\"Fallback meta description\",\"email\":\"mail@domain.tld\",\"image\":{\"@type\":\"ImageObject\",\"height\":933,\"url\":\"http://localhost/media/images/sites/identity/image/xlarge/20ri181teifg.jpg\",\"width\":1900},\"name\":\"Organization name\",\"sameAs\":[\"https://instagram.com/test\",\"https://facebook.com/test\"],\"url\":\"https://www.domain.tld\"}",
                60,
                47,
                "script",
                62
              ]}

    {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})
    Brando.Sites.update_seo(seo, %{fallback_meta_image: nil}, :system)
  end

  test "render json ld :breadcrumbs" do
    {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})
    Brando.Sites.update_seo(seo, %{fallback_meta_image: nil}, :system)

    breadcrumbs = [
      {"Home", "/"},
      {"About", "/about"},
      {"Contact", "/about/contact"}
    ]

    mock_conn =
      %Plug.Conn{}
      |> Brando.Plug.I18n.put_locale(skip_session: true)
      |> Brando.Plug.HTML.put_json_ld(:breadcrumbs, breadcrumbs)

    rendered_json_ld = Brando.HTML.render_json_ld(mock_conn)

    assert rendered_json_ld == [
             {
               :safe,
               [
                 60,
                 "script",
                 [32, "type", 61, 34, "application/ld+json", 34],
                 62,
                 "{\"@context\":\"https://schema.org\",\"@type\":\"BreadcrumbList\",\"itemListElement\":[{\"@type\":\"ListItem\",\"item\":\"/\",\"name\":\"Home\",\"position\":1},{\"@type\":\"ListItem\",\"item\":\"/about\",\"name\":\"About\",\"position\":2},{\"@type\":\"ListItem\",\"item\":\"/about/contact\",\"name\":\"Contact\",\"position\":3}]}",
                 60,
                 47,
                 "script",
                 62
               ]
             },
             {
               :safe,
               [
                 60,
                 "script",
                 [32, "type", 61, 34, "application/ld+json", 34],
                 62,
                 "{\"@context\":\"http://schema.org\",\"@id\":\"http://localhost/#identity\",\"@type\":\"Organization\",\"address\":{\"@type\":\"PostalAddress\",\"addressCountry\":\"NO\",\"addressLocality\":\"Oslo\",\"addressRegion\":\"Oslo\",\"postalCode\":\"0000\"},\"alternateName\":\"Shortform name\",\"description\":\"Fallback meta description\",\"email\":\"mail@domain.tld\",\"name\":\"Organization name\",\"sameAs\":[\"https://instagram.com/test\",\"https://facebook.com/test\"],\"url\":\"https://www.domain.tld\"}",
                 60,
                 47,
                 "script",
                 62
               ]
             },
             []
           ]
  end
end
