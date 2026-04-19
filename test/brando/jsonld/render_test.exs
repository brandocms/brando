defmodule Brando.JSONLDRenderTest do
  use ExUnit.Case
  use Brando.ConnCase, async: false
  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Brando.HTML

  alias Brando.Factory

  @mock_data %{
    __meta__: %{
      current_url: "http://localhost"
    },
    inserted_at: ~N[2000-01-01 23:00:00],
    updated_at: ~N[2000-01-01 23:30:00],
    language: "no",
    title: "Title of page",
    meta_description: "Meta description",
    meta_image: nil
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
    width: 1900,
    config_target: "image:Brando.Sites.SEO:fallback_meta_image"
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

  defp extract_graph(rendered_comp) do
    [json_string] =
      ~r/<script[^>]*>([\s\S]*?)<\/script>/
      |> Regex.run(rendered_comp, capture: :all_but_first)

    Jason.decode!(json_string)
  end

  defp find_entity(graph, type) do
    Enum.find(graph["@graph"], &(&1["@type"] == type))
  end

  test "render json ld as @graph" do
    u0 = Factory.insert(:random_user)
    {:ok, fallback_meta_image} = Brando.Images.create_image(@img, u0)
    {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}, preload: [:logo]})
    Brando.Sites.update_identity(identity.id, %{links: @links}, :system)

    {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})
    Brando.Sites.update_seo(seo, %{fallback_meta_image_id: fallback_meta_image.id}, :system)

    mock_conn =
      %Plug.Conn{}
      |> Brando.Plug.I18n.put_locale(skip_session: true)
      |> Brando.Plug.HTML.put_json_ld(Brando.Pages.Page, @mock_data)

    assigns = %{mock_conn: mock_conn}

    comp = ~H"""
    <.render_json_ld conn={@mock_conn} />
    """

    rendered_comp = rendered_to_string(comp)
    graph = extract_graph(rendered_comp)

    # Single top-level @context
    assert graph["@context"] == "https://schema.org"
    assert is_list(graph["@graph"])

    # Identity entity
    identity_json = find_entity(graph, "Organization")
    assert identity_json["@id"] == "http://localhost/#identity"
    assert identity_json["name"] == "Organization name"
    assert identity_json["email"] == "mail@domain.tld"
    assert identity_json["telephone"] == "+47 00 00 00 00"
    assert identity_json["alternateName"] == "Shortform name"
    assert identity_json["description"] == "Fallback meta description"
    assert identity_json["url"] == "https://www.domain.tld"
    assert identity_json["sameAs"] == ["https://instagram.com/test", "https://facebook.com/test"]

    assert identity_json["address"] == %{
             "@type" => "PostalAddress",
             "addressCountry" => "NO",
             "addressLocality" => "Oslo",
             "postalCode" => "0000",
             "streetAddress" => "Testveien 1"
           }

    assert identity_json["image"] == %{
             "@type" => "ImageObject",
             "height" => 933,
             "url" => "http://localhost/media/images/sites/identity/image/xlarge/20ri181teifg.jpg",
             "width" => 1900
           }

    # No @context on individual entities (it's at the top level)
    refute Map.has_key?(identity_json, "@context")

    # WebSite entity
    website_json = find_entity(graph, "WebSite")
    assert website_json["@id"] == "http://localhost/#website"
    assert website_json["name"] == "Organization name"
    assert website_json["publisher"] == %{"@id" => "http://localhost/#identity"}
    refute Map.has_key?(website_json, "@context")

    # Article entity
    article_json = find_entity(graph, "Article")
    assert article_json["author"] == %{"@id" => "http://localhost/#identity"}
    assert article_json["copyrightHolder"] == %{"@id" => "http://localhost/#identity"}
    assert article_json["copyrightYear"] == 2000
    assert article_json["creator"] == %{"@id" => "http://localhost/#identity"}
    assert article_json["dateModified"] == "2000-01-01T23:30:00Z"
    assert article_json["datePublished"] == "2000-01-01T23:00:00Z"
    assert article_json["description"] == "Meta description"
    assert article_json["headline"] == "Title of page"
    assert article_json["inLanguage"] == "no"
    assert article_json["mainEntityOfPage"] == "http://localhost"
    assert article_json["name"] == "Title of page"
    assert article_json["publisher"] == %{"@id" => "http://localhost/#identity"}
    assert article_json["url"] == "http://localhost"
    refute Map.has_key?(article_json, "@context")

    {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})
    Brando.Sites.update_seo(seo, %{fallback_meta_image_id: nil}, :system)
  end

  test "render json ld @graph with breadcrumbs" do
    {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})

    Brando.Sites.update_seo(
      seo,
      %{fallback_meta_image_id: nil},
      :system
    )

    breadcrumbs = [
      {"Home", "/"},
      {"About", "/about"},
      {"Contact", "/about/contact"}
    ]

    mock_conn =
      %Plug.Conn{}
      |> Brando.Plug.I18n.put_locale(skip_session: true)
      |> Brando.Plug.HTML.put_json_ld(:breadcrumbs, breadcrumbs)

    assigns = %{mock_conn: mock_conn}

    comp = ~H"""
    <.render_json_ld conn={@mock_conn} />
    """

    rendered_comp = rendered_to_string(comp)
    graph = extract_graph(rendered_comp)

    assert graph["@context"] == "https://schema.org"

    breadcrumbs_json = find_entity(graph, "BreadcrumbList")

    assert breadcrumbs_json["itemListElement"] == [
             %{"@type" => "ListItem", "item" => "http://localhost", "name" => "Home", "position" => 1},
             %{"@type" => "ListItem", "item" => "http://localhost/about", "name" => "About", "position" => 2},
             %{"@type" => "ListItem", "item" => "http://localhost/about/contact", "name" => "Contact", "position" => 3}
           ]

    refute Map.has_key?(breadcrumbs_json, "@context")
  end
end
