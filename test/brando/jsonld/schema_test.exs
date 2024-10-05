defmodule Brando.JSONLDSchemaTest do
  use ExUnit.Case, async: false

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

  @extra_fields [
    %{name: :image, type: :image, value_fn: &__MODULE__.get_org_image/1},
    %{name: :copyrightYear, type: :integer, value_fn: &__MODULE__.get_year/1}
  ]

  @image %Brando.Images.Image{
    credits: nil,
    path: "images/avatars/27i97a.jpeg",
    title: nil,
    width: 900,
    height: 900,
    sizes: %{
      "thumb" => "images/avatars/thumb/27i97a.jpeg",
      "small" => "images/avatars/small/27i97a.jpeg",
      "medium" => "images/avatars/medium/27i97a.jpeg",
      "xlarge" => "images/avatars/large/27i97a.jpeg"
    }
  }

  def get_org_image(_), do: @image
  def get_year(data), do: data.inserted_at.year

  test "extract json-ld" do
    extracted_json_ld = Brando.JSONLD.extract_json_ld(Brando.Pages.Page, @mock_data)

    assert extracted_json_ld ==
             %Brando.JSONLD.Schema.Article{
               "@context": "http://schema.org",
               "@type": "Article",
               author: %{"@id": "http://localhost/#identity"},
               copyrightHolder: %{"@id": "http://localhost/#identity"},
               copyrightYear: 2000,
               creator: %{"@id": "http://localhost/#identity"},
               dateModified: "2000-01-01T23:30:00Z",
               datePublished: "2000-01-01T23:00:00Z",
               description: "Meta description",
               headline: "Title of page",
               image: nil,
               inLanguage: "no",
               mainEntityOfPage: "http://localhost",
               name: "Title of page",
               publisher: %{"@id": "http://localhost/#identity"},
               url: "http://localhost"
             }

    extracted_json_ld =
      Brando.JSONLD.extract_json_ld(
        Brando.Pages.Page,
        @mock_data,
        @extra_fields
      )

    assert extracted_json_ld ==
             %Brando.JSONLD.Schema.Article{
               "@context": "http://schema.org",
               "@type": "Article",
               author: %{"@id": "http://localhost/#identity"},
               copyrightHolder: %{"@id": "http://localhost/#identity"},
               copyrightYear: 2000,
               creator: %{"@id": "http://localhost/#identity"},
               dateModified: "2000-01-01T23:30:00Z",
               datePublished: "2000-01-01T23:00:00Z",
               description: "Meta description",
               headline: "Title of page",
               image: %Brando.JSONLD.Schema.ImageObject{
                 "@type": "ImageObject",
                 height: 900,
                 url: "http://localhost/media/images/avatars/large/27i97a.jpeg",
                 width: 900
               },
               inLanguage: "no",
               mainEntityOfPage: "http://localhost",
               name: "Title of page",
               publisher: %{"@id": "http://localhost/#identity"},
               url: "http://localhost"
             }
  end

  test "Brando.JSONLD.Schema.Corporation" do
    cached_identity = Brando.Cache.Identity.get("en")
    cached_seo = Brando.Cache.SEO.get("en")

    assert Brando.JSONLD.Schema.Corporation.build({cached_identity, cached_seo}) ==
             %Brando.JSONLD.Schema.Corporation{
               "@context": "http://schema.org",
               "@id": "http://localhost/#identity",
               "@type": "Corporation",
               address: %Brando.JSONLD.Schema.PostalAddress{
                 "@type": "PostalAddress",
                 addressCountry: "NO",
                 addressLocality: "Oslo",
                 addressRegion: "Oslo",
                 postalCode: "0000",
                 streetAddress: "Testveien 1"
               },
               alternateName: "Shortform name",
               description: "Fallback meta description",
               email: "mail@domain.tld",
               image: nil,
               logo: nil,
               name: "Organization name",
               sameAs: ["https://instagram.com/test", "https://facebook.com/test"],
               url: "https://www.domain.tld",
               telephone: "+47 00 00 00 00"
             }
  end

  test "Brando.JSONLD.Schema.Person" do
    u1 = %{
      name: "James Williamson",
      image: @image
    }

    assert Brando.JSONLD.Schema.Person.build(u1) == %Brando.JSONLD.Schema.Person{
             "@context": "http://schema.org",
             "@type": "Person",
             image: %Brando.JSONLD.Schema.ImageObject{
               "@type": "ImageObject",
               height: 900,
               url: "http://localhost/media/images/avatars/large/27i97a.jpeg",
               width: 900
             },
             name: "James Williamson"
           }
  end

  test "Brando.JSONLD.Schema.WebSite" do
    w = %{
      name: "My website",
      url: "https://test.com"
    }

    assert Brando.JSONLD.Schema.WebSite.build(w) == %Brando.JSONLD.Schema.WebSite{
             "@context": "http://schema.org",
             "@type": "WebSite",
             name: "My website",
             url: "https://test.com"
           }
  end

  test "date" do
    assert Brando.JSONLD.to_date(~D[2020-01-01]) == "2020-01-01"
  end

  test "datetime" do
    assert Brando.JSONLD.to_datetime(~N[2021-10-08 07:56:00.000000]) ==
             "2021-10-08T07:56:00.000000Z"
  end
end
