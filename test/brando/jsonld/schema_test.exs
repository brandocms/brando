defmodule Brando.JSONLDSchemaTest do
  use ExUnit.Case, async: true

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

  @image %Brando.Type.Image{
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
        Brando.JSONLD.Schema.convert_format(@extra_fields)
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
end
