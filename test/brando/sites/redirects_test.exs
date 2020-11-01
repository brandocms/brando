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
    assert Redirects.test_redirect(@test_path) == {:error, {:redirects, :no_match}}
    Sites.update_seo(@seo_params, :system)
    assert Redirects.test_redirect(@test_path) == {:ok, {:redirect, {"/new/projects", "302"}}}
  end
end
