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

  test "render json ld" do
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

    extracted_json =
      ~r/<script[^>]*>([^<]+|<(?!\/script>))+/
      |> Regex.run(rendered_comp, capture: :all_but_first)
      |> List.first()
      |> Jason.decode!()

    assert extracted_json == %{
             "@context" => "http://schema.org",
             "@id" => "http://localhost/#identity",
             "@type" => "Organization",
             "address" => %{
               "@type" => "PostalAddress",
               "addressCountry" => "NO",
               "addressLocality" => "Oslo",
               "addressRegion" => "Oslo",
               "postalCode" => "0000"
             },
             "alternateName" => "Shortform name",
             "description" => "Fallback meta description",
             "email" => "mail@domain.tld",
             "image" => %{
               "@type" => "ImageObject",
               "height" => 933,
               "url" =>
                 "http://localhost/media/images/sites/identity/image/xlarge/20ri181teifg.jpg",
               "width" => 1900
             },
             "name" => "Organization name",
             "sameAs" => ["https://instagram.com/test", "https://facebook.com/test"],
             "url" => "https://www.domain.tld"
           }

    {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})
    Brando.Sites.update_seo(seo, %{fallback_meta_image_id: nil}, :system)
  end

  test "render json ld :breadcrumbs" do
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

    extracted_json =
      ~r/<script[^>]*>([^<]+|<(?!\/script>))+/
      |> Regex.run(rendered_comp, capture: :all_but_first)
      |> List.first()
      |> Jason.decode!()

    assert extracted_json == %{
             "@context" => "http://schema.org",
             "@id" => "http://localhost/#identity",
             "@type" => "Organization",
             "address" => %{
               "@type" => "PostalAddress",
               "addressCountry" => "NO",
               "addressLocality" => "Oslo",
               "addressRegion" => "Oslo",
               "postalCode" => "0000"
             },
             "alternateName" => "Shortform name",
             "description" => "Fallback meta description",
             "email" => "mail@domain.tld",
             "name" => "Organization name",
             "sameAs" => ["https://instagram.com/test", "https://facebook.com/test"],
             "url" => "https://www.domain.tld"
           }
  end
end
