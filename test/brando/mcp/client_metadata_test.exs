defmodule Brando.MCP.ClientMetadataTest do
  # Client ID Metadata Documents: what a client's document must say, and
  # where a client may send the person back to.
  use Brando.ConnCase, async: false

  alias Brando.MCP.ClientMetadata

  @id "https://client.example/oauth/client.json"

  defp doc(fields \\ %{}),
    do:
      Map.merge(
        %{"client_id" => @id, "client_name" => "Client", "redirect_uris" => ["https://client.example/cb"]},
        fields
      )

  test "client ids are https URLs with a path and nothing else" do
    assert ClientMetadata.valid_client_id?(@id)

    for bad <- [
          "http://client.example/c.json",
          "https://client.example",
          "https://client.example/",
          "https://user:pw@client.example/c.json",
          "https://client.example/c.json?x=1",
          "https://client.example/c.json#x",
          "https://client.example:8443/c.json",
          "https://client.example:80/c.json",
          "https://client.example/a/../c.json",
          "client",
          nil,
          "https://client.example/" <> String.duplicate("a", 600)
        ] do
      refute ClientMetadata.valid_client_id?(bad), inspect(bad)
    end
  end

  test "the site's own host, and its media and CDN hosts, are never clients" do
    own = URI.parse(Brando.MCP.base_url()).host
    refute ClientMetadata.valid_client_id?("https://#{own}/media/client.json")
    assert ClientMetadata.valid_client_id?("https://client.example:443/oauth/client.json")

    original = Application.get_env(:brando, :media_url)
    Application.put_env(:brando, :media_url, "https://media.example.com/media")
    on_exit(fn -> Application.put_env(:brando, :media_url, original) end)
    refute ClientMetadata.valid_client_id?("https://media.example.com/media/client.json")
  end

  test "nor any site environment's domain" do
    site =
      %Brando.Sites.Site{}
      |> Brando.Sites.Site.changeset(%{
        name: "Acme",
        key: "acme",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })
      |> Brando.Repo.insert!()

    %Brando.Environments.Environment{}
    |> Brando.Environments.Environment.changeset(%{
      site_id: site.id,
      name: "Staging",
      key: "staging",
      domain: "Staging.Acme.TEST"
    })
    |> Brando.Repo.insert!()

    refute ClientMetadata.valid_client_id?("https://staging.acme.test/uploads/client.json")
    assert ClientMetadata.valid_client_id?("https://client.example/oauth/client.json")
  end

  test "a document names itself, the client and its redirect URIs" do
    assert {:ok, %{client_name: "Client", host: "client.example"}} = ClientMetadata.parse(@id, Jason.encode!(doc()))

    for bad <- [
          doc(%{"client_id" => "https://client.example/other.json"}),
          doc(%{"client_name" => nil}),
          doc(%{"client_name" => "  "}),
          doc(%{"redirect_uris" => []}),
          doc(%{"redirect_uris" => ["http://client.example/cb"]}),
          doc(%{"redirect_uris" => ["myapp://cb"]}),
          doc(%{"redirect_uris" => ["https://client.example/cb#x"]}),
          doc(%{"token_endpoint_auth_method" => "client_secret_basic"}),
          doc(%{"client_secret" => "s3cret"}),
          doc(%{"grant_types" => ["client_credentials"]}),
          doc(%{"response_types" => ["token"]})
        ] do
      assert {:error, :invalid_document} = ClientMetadata.parse(@id, bad), inspect(bad)
    end

    assert {:error, :invalid_document} = ClientMetadata.parse(@id, "not json")
    assert {:error, :invalid_document} = ClientMetadata.parse(@id, "[1]")
  end

  test "a name is one line of printable text, at most 80 characters" do
    rlo = <<0x202E::utf8>>

    {:ok, client} =
      ClientMetadata.parse(@id, doc(%{"client_name" => "Evil\n" <> rlo <> "app\u0000 " <> String.duplicate("x", 200)}))

    refute client.client_name =~ "\n"
    refute client.client_name =~ rlo
    assert String.length(client.client_name) <= 80
  end

  test "redirect URIs match exactly, except a loopback port" do
    {:ok, client} =
      ClientMetadata.parse(
        @id,
        doc(%{"redirect_uris" => ["https://client.example/cb", "http://127.0.0.1/callback", "http://localhost/callback"]})
      )

    assert ClientMetadata.redirect_allowed?(client, "https://client.example/cb")
    assert ClientMetadata.redirect_allowed?(client, "http://127.0.0.1:51234/callback")
    assert ClientMetadata.redirect_allowed?(client, "http://localhost:3118/callback")

    refute ClientMetadata.redirect_allowed?(client, "https://client.example/cb/")
    refute ClientMetadata.redirect_allowed?(client, "https://client.example:8443/cb")
    refute ClientMetadata.redirect_allowed?(client, "https://client.example/cb?next=https://evil.example")
    refute ClientMetadata.redirect_allowed?(client, "https://evil.example/cb")
    refute ClientMetadata.redirect_allowed?(client, "http://127.0.0.1:51234/other")
    refute ClientMetadata.redirect_allowed?(client, "http://127.0.0.2:51234/callback")
    refute ClientMetadata.redirect_allowed?(client, "http://evil.example/callback")
    refute ClientMetadata.redirect_allowed?(client, nil)
  end

  test "documents are only fetched from public https addresses" do
    # No fetcher configured: the real fetch runs through the webhooks' URL guard.
    assert {:error, :unreachable} = ClientMetadata.fetch("https://127.0.0.1/client.json")
    assert {:error, :unreachable} = ClientMetadata.fetch("https://10.0.0.1/client.json")
    assert {:error, :invalid_client_id} = ClientMetadata.fetch("http://client.example/client.json")
  end
end
