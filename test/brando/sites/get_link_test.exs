defmodule Brando.Sites.GetLinkTest do
  # Not async: it writes the node's identity cache
  use Brando.ConnCase, async: false

  import Brando.Test.Support, only: [preserve_cache: 1, put_test_env: 2]

  alias Brando.Sites
  alias Brando.Sites.Identity
  alias Brando.Sites.Link
  alias Brando.Tenant

  @prefix "tenant_get-link-acme_production"

  setup do
    preserve_cache(:identity)

    Brando.Cache.put(
      :identity,
      %{
        "en" => %Identity{
          language: :en,
          links: [
            %Link{name: "Instagram", url: "https://instagram.com/en"},
            %Link{name: "Script", url: "javascript:alert(1)"}
          ],
          languages: [%{id: 1, name: "English"}]
        },
        "no" => %Identity{
          language: :no,
          links: [%Link{name: "Instagram", url: "https://instagram.com/no"}],
          languages: [%{id: 1, name: "Engelsk"}]
        }
      },
      :infinite
    )

    :ok
  end

  describe "get_link/2" do
    test "returns the URL of the link in that language's identity, matched without regard to case" do
      assert Sites.get_link("en", "instagram") == "https://instagram.com/en"
      assert Sites.get_link("no", "INSTAGRAM") == "https://instagram.com/no"
      assert Sites.get_link(:no, "Instagram") == "https://instagram.com/no"
    end

    test "returns an empty string for a missing link, language or identity" do
      assert Sites.get_link("en", "mastodon") == ""
      assert Sites.get_link("de", "instagram") == ""
      assert Sites.get_link(nil, "instagram") == ""
    end

    test "returns an empty string for a script URL" do
      assert Sites.get_link("en", "script") == ""
    end

    test "reads the current site's identity" do
      key = {:tenant, @prefix, :identity}
      cached = Cachex.get!(:cache, key)

      on_exit(fn ->
        if cached, do: Cachex.put!(:cache, key, cached), else: Cachex.del!(:cache, key)
      end)

      Cachex.put!(:cache, key, %{
        "en" => %Identity{links: [%Link{name: "Instagram", url: "https://instagram.com/acme"}]}
      })

      put_test_env(:tenancy_mode, :multi)
      Tenant.put_prefix(@prefix)
      on_exit(fn -> Tenant.put_prefix(nil) end)

      assert Sites.get_link("en", "instagram") == "https://instagram.com/acme"
      assert Sites.get_link("no", "instagram") == ""
    end
  end

  describe "get_link/1" do
    test "returns the URL of the link in the default language's identity" do
      assert Brando.Languages.default_language() == "en"
      assert Sites.get_link("instagram") == "https://instagram.com/en"
      assert Sites.get_link("mastodon") == ""
    end
  end

  describe "get_language/2" do
    test "returns the name of the entry with the id in that language's identity" do
      assert Sites.get_language("en", 1) == "English"
      assert Sites.get_language("no", 1) == "Engelsk"
      assert Sites.get_language("no", 2) == nil
      assert Sites.get_language("de", 1) == nil
    end

    test "returns nil when the identity has no languages" do
      Brando.Cache.put(:identity, %{"en" => %Identity{links: []}}, :infinite)

      assert Sites.get_language("en", 1) == nil
    end
  end

  describe "get_language/1" do
    test "reads the default language's identity" do
      assert Sites.get_language(1) == "English"
      assert Sites.get_language(2) == nil
    end
  end
end
