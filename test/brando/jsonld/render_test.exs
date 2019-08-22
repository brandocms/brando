defmodule Brando.JSONLDRenderTest do
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

  test "render json ld" do
    mock_conn = Brando.Plug.HTML.put_json_ld(%Plug.Conn{}, Brando.Pages.Page, @mock_data)

    rendered_json_ld = Brando.HTML.render_json_ld(mock_conn)

    assert rendered_json_ld == [
             [],
             {:safe,
              [
                60,
                "script",
                [[32, "type", 61, 34, "application/ld+json", 34]],
                62,
                "{\"@context\":\"http://schema.org\",\"@id\":\"http://localhost/#identity\",\"@type\":\"Organization\",\"address\":{\"@type\":\"PostalAddress\",\"addressCountry\":\"NO\",\"addressLocality\":\"Oslo\",\"addressRegion\":\"Oslo\",\"postalCode\":\"0000\"},\"alternateName\":\"Kortversjon av navnet\",\"description\":\"Beskrivelse av organisasjonen/nettsiden\",\"email\":\"mail@domain.tld\",\"name\":\"Organisasjonens navn\",\"url\":\"https://www.domain.tld\"}",
                60,
                47,
                "script",
                62
              ]},
             {:safe,
              [
                60,
                "script",
                [[32, "type", 61, 34, "application/ld+json", 34]],
                62,
                "{\"@context\":\"http://schema.org\",\"@type\":\"Article\",\"author\":{\"@id\":\"http://localhost/#identity\"},\"copyrightHolder\":{\"@id\":\"http://localhost/#identity\"},\"copyrightYear\":2000,\"creator\":{\"@id\":\"http://localhost/#creator\"},\"dateModified\":\"2000-01-01T23:30:00Z\",\"datePublished\":\"2000-01-01T23:00:00Z\",\"description\":\"Meta description\",\"headline\":\"Title of page\",\"inLanguage\":\"no\",\"mainEntityOfPage\":\"http://localhost\",\"name\":\"Title of page\",\"publisher\":{\"@id\":\"http://localhost/#creator\"},\"url\":\"http://localhost\"}",
                60,
                47,
                "script",
                62
              ]}
           ]
  end
end
