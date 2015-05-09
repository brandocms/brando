#Code.require_file("router_helper.exs", Path.join([__DIR__, "..", ".."]))

defmodule Brando.ImageCategory.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.ImageCategory
  alias Brando.User
  alias Brando.Type.ImageConfig

  @user_params %{"avatar" => nil, "role" => ["2", "4"],
                 "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
                 "password" => "finimeze", "status" => "1",
                 "submit" => "Submit", "username" => "zabuzasixu"}
  @params %{"cfg" => %ImageConfig{}, "name" => "Test Category", "slug" => "test-category"}
  @broken_params %{"cfg" => %ImageConfig{}}

  def create_user do
    {:ok, user} = User.create(@user_params)
    user
  end

  test "new" do
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/kategorier/ny")
    assert html_response(conn, 200) =~ "Ny bildekategori"
  end

  test "edit" do
    user = create_user
    assert {:ok, category} = ImageCategory.create(@params, user)
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/kategorier/#{category.id}/endre")
    assert html_response(conn, 200) =~ "Endre bildekategori"
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/kategorier/1234/endre")
    assert html_response(conn, 404)
  end

  test "create (post) w/params" do
    user = create_user
    params = Map.put(@params, "creator_id", user.id)
    conn = call_with_custom_user(RouterHelper.TestRouter, :post, "/admin/bilder/kategorier/", %{"imagecategory" => params}, user: user)
    assert redirected_to(conn, 302) =~ "/admin/bilder"
    assert get_flash(conn, :notice) == "Kategori opprettet."
  end

  test "create (post) w/erroneus params" do
    conn = call_with_user(RouterHelper.TestRouter, :post, "/admin/bilder/kategorier/", %{"imagecategory" => @broken_params})
    assert html_response(conn, 200) =~ "Ny bildekategori"
    assert get_flash(conn, :error) == "Feil i skjema"
  end

  test "update (post) w/params" do
    user = create_user
    params = Map.put(@params, "creator_id", user.id)
    assert {:ok, category} = ImageCategory.create(params, user)
    conn = call_with_user(RouterHelper.TestRouter, :patch, "/admin/bilder/kategorier/#{category.id}", %{"imagecategory" => params})
    assert redirected_to(conn, 302) =~ "/admin/bilder"
    assert get_flash(conn, :notice) == "Kategori oppdatert."
  end

  test "config (get)" do
    user = create_user
    assert {:ok, category} = ImageCategory.create(@params, user)
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/kategorier/#{category.id}/konfigurer")
    assert html_response(conn, 200) =~ "Konfigurér bildekategori"
    assert html_response(conn, 200) =~ "imagecategoryconfig[cfg]"
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/kategorier/1234/konfigurer")
    assert html_response(conn, 404)
  end

  test "config (post) w/params" do
    user = create_user
    params = Map.put(@params, "creator_id", user.id)
    assert {:ok, category} = ImageCategory.create(params, user)
    conn = call_with_user(RouterHelper.TestRouter, :patch, "/admin/bilder/kategorier/#{category.id}/konfigurer", %{"imagecategoryconfig" => params})
    assert redirected_to(conn, 302) =~ "/admin/bilder"
    assert get_flash(conn, :notice) == "Kategori konfigurert."
  end

  test "delete_confirm" do
    user = create_user
    assert {:ok, category} = ImageCategory.create(@params, user)
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/kategorier/#{category.id}/slett")
    assert html_response(conn, 200) =~ "Slett bildekategori: Test Category"
  end

  test "delete" do
    user = create_user
    assert {:ok, category} = ImageCategory.create(@params, user)
    conn = call_with_user(RouterHelper.TestRouter, :delete, "/admin/bilder/kategorier/#{category.id}")
    assert redirected_to(conn, 302) =~ "/admin/bilder"
    assert get_flash(conn, :notice) == "bildekategori Test Category slettet."
  end
end