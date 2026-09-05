defmodule Brando.Sites.RedirectsTest do
  use ExUnit.Case
  use Brando.ConnCase
  use BrandoIntegration.TestCase
  alias Brando.Sites
  alias Brando.Sites.Redirects
  @test_path ["test", "projects"]
  @seo_params %{
    "redirects" => [
      %{"from" => "/test/:slug", "to" => "/new/:slug", "code" => "302"},
      %{"from" => "/teststart", "to" => "/new/teststart", "code" => "301"},
      %{"from" => "/test-final$", "to" => "/new/test-final", "code" => "301"}
    ]
  }

  setup do
    Brando.Cache.SEO.set()
    :ok
  end

  test "redirects" do
    assert Redirects.test_redirect(@test_path, "en") == {:error, {:redirects, :no_match}}
    {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})
    Sites.update_seo(seo, @seo_params, :system)

    assert Redirects.test_redirect(@test_path, "en") == {:ok, {:redirect, {"/new/projects", 302}}}

    assert Redirects.test_redirect(["something", "teststart"], "en") ==
             {:error, {:redirects, :no_match}}

    assert Redirects.test_redirect(["teststart"], "en") ==
             {:ok, {:redirect, {"/new/teststart", 301}}}

    assert Redirects.test_redirect(["teststart", "more"], "en") ==
             {:ok, {:redirect, {"/new/teststart", 301}}}

    assert Redirects.test_redirect(["test-final"], "en") ==
             {:ok, {:redirect, {"/new/test-final", 301}}}

    assert Redirects.test_redirect(["test-final", "more"], "en") ==
             {:error, {:redirects, :no_match}}
  end

  test "confirmed permalinks match the exact literal path and refresh the cache" do
    proposal = %{from: "/old.v1/:literal", to: "/new", language: "en"}
    assert {:ok, _} = Redirects.create_permalink_redirect(proposal, :system)
    assert Redirects.test_redirect(["old.v1", ":literal"], "en") == {:ok, {:redirect, {"/new", 301}}}
    assert Redirects.test_redirect(["oldXv1", ":literal"], "en") == {:error, {:redirects, :no_match}}
    assert Redirects.test_redirect(["old.v1", "anything"], "en") == {:error, {:redirects, :no_match}}
    assert Redirects.test_redirect(["old.v1", ":literal", "child"], "en") == {:error, {:redirects, :no_match}}
    assert Redirects.test_redirect(["old.v1", ":literal"], "no") == {:error, {:redirects, :no_match}}
  end

  test "preserves unrelated rules and replaces duplicate sources" do
    {:ok, seo} = Sites.get_seo(%{matches: %{language: "en"}})
    assert {:ok, _} = Sites.update_seo(seo, @seo_params, :system)
    proposal = %{from: "/old", to: "/new", language: "en"}
    assert {:ok, _} = Redirects.create_permalink_redirect(proposal, :system)
    assert {:ok, seo} = Redirects.create_permalink_redirect(%{proposal | to: "/newer"}, :system)
    assert length(seo.redirects) == 4
    assert Redirects.test_redirect(["old"], "en") == {:ok, {:redirect, {"/newer", 301}}}
    assert Redirects.test_redirect(@test_path, "en") == {:ok, {:redirect, {"/new/projects", 302}}}
  end

  test "successive renames avoid redirect chains and renaming back avoids a loop" do
    assert {:ok, _} = Redirects.create_permalink_redirect(%{from: "/a", to: "/b", language: "en"}, :system)
    assert {:ok, _} = Redirects.create_permalink_redirect(%{from: "/b", to: "/c", language: "en"}, :system)
    assert Redirects.test_redirect(["a"], "en") == {:ok, {:redirect, {"/c", 301}}}
    assert {:ok, _} = Redirects.create_permalink_redirect(%{from: "/c", to: "/a", language: "en"}, :system)
    assert Redirects.test_redirect(["a"], "en") == {:error, {:redirects, :no_match}}
    assert Redirects.test_redirect(["b"], "en") == {:ok, {:redirect, {"/a", 301}}}
    assert Redirects.test_redirect(["c"], "en") == {:ok, {:redirect, {"/a", 301}}}
  end

  test "reports missing SEO settings without creating a redirect in another language" do
    assert {:error, :seo_not_found} =
             Redirects.create_permalink_redirect(%{from: "/old", to: "/new", language: "no"}, :system)
  end
end
