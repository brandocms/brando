defmodule Brando.Sites.RedirectsTest do
  use ExUnit.Case
  use Brando.ConnCase
  use BrandoIntegration.TestCase
  alias Brando.Sites
  alias Brando.Sites.Redirects
  @test_path ["test", "projects"]
  @seo_params %{
    "redirects" => [
      %{"from" => "/test/:slug", "to" => "/new/:slug", "code" => "302"}
    ]
  }

  test "redirects" do
    assert Redirects.test_redirect(@test_path, "en") == {:error, {:redirects, :no_match}}
    {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})
    Sites.update_seo(seo, @seo_params, :system)
    assert Redirects.test_redirect(@test_path, "en") == {:ok, {:redirect, {"/new/projects", 302}}}
  end
end
