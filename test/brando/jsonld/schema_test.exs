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
    {:image, Brando.JSONLD.Schema.ImageObject, &__MODULE__.get_org_image/1},
    {:copyrightYear, :string, [:inserted_at, :year]}
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

  def get_org_image(_) do
    @image
  end

  import CompileTimeAssertions

  test "field without populator function raises" do
    assert_compile_time_raise(RuntimeError, "requires a populator function - someField", fn ->
      import Brando.Blueprint.JSONLD
      json_ld_field("someField", Brando.JSONLD.Schema.ImageObject, nil)
    end)
  end

  test "field without schema raises" do
    assert_compile_time_raise(RuntimeError, "requires a schema as second arg - someField", fn ->
      import Brando.Blueprint.JSONLD
      json_ld_field("someField", "what is this?", :something)
    end)
  end

  test "convert_format raises on missing populator" do
    assert_raise RuntimeError, fn ->
      Brando.JSONLD.convert_format([
        {"fieldName", Brando.JSONLD.Schema.ImageObject, nil}
      ])
    end
  end

  test "convert_format raises on binary schema" do
    assert_raise RuntimeError, fn ->
      Brando.JSONLD.convert_format([
        {"fieldName", "Binary.Schema", :dummy}
      ])
    end
  end

  test "extract json-ld" do
    extracted_json_ld = Brando.Pages.Page.extract_json_ld(@mock_data)

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
      Brando.Pages.Page.extract_json_ld(
        @mock_data,
        Brando.JSONLD.convert_format(@extra_fields)
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
                 postalCode: "0000"
               },
               alternateName: "Shortform name",
               description: "Fallback meta description",
               email: "mail@domain.tld",
               image: nil,
               logo: nil,
               name: "Organization name",
               sameAs: ["https://instagram.com/test", "https://facebook.com/test"],
               url: "https://www.domain.tld"
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
end
